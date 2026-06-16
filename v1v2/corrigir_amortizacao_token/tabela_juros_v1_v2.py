"""
tabela_juros_v1_v2.py
---------------------------------------------------------------------------------------
Tabela caso-a-caso (TODOS os eventos de amortizacao) com PRECO TOTAL (dirty = clean +
accrued) em D-1 e D0, no V1 e no V2, mais:
  - Juros Pago V1  = metadata `amortization` (interest_payment+scheduled+extraordinary)
  - Juros Pago V2  = PrecoTotal(D0, horario anterior) - PrecoTotal(D0, evento)
                     i.e. a QUEDA do preco total no mesmo dia (00:00 -> evento), sem
                     contaminacao de accrued de outro dia.
  - Bate?          = |juros_V1 - juros_V2| < TOL

READ-ONLY nos dois bancos. V2 local (127.0.0.1/engine); V1 prod (sessao read-only).
Le URLs do .env desta pasta (DATABASE_URL, V1_DATABASE_URL). Nao escreve nada nos bancos.

D0  = data do evento de amortizacao.
D-1 = ultima data de valuation ANTERIOR a D0 (EOD do dia anterior).
No V2 a "D0 horario anterior" = a diaria 00:00 do proprio D0 (pre-evento); o "evento" = a
linha com cash_flow<>0 (09:00). No V1, value=PU pos-amort, metadata.last_value=PU pre-amort.

Saida: console + CSV (tabela_juros_v1_v2.csv) nesta pasta.
"""
from __future__ import annotations
import os, re
from decimal import Decimal
import psycopg2, psycopg2.extras
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
TOL = 0.001  # tolerancia de match em PU (matches batem a ~1e-6; glitch ~0.058)

# V2 name -> V1 full_name (recon 2026-06-09, 1:1 confirmado)
PARES = [
    ("CR-FGTS-01-01-SINGLE",        "CR-FGTS-01-01-single-01"),
    ("CR-FGTS-02-01-SINGLE",        "CR-FGTS-02-01-single-01"),
    ("CR-FGTS-03-01-SINGLE",        "CR-FGTS-03-01-single-01"),
    ("CR-FGTS-04-01-SINGLE",        "CR-FGTS-04-01-single-01"),
    ("CR-FGTS-05-01-SINGLE",        "CR-FGTS-05-01-single-01"),
    ("CR-FGTS-06-01-SINGLE",        "CR-FGTS-06-01-single-01"),
    ("CR-FGTS-07-01-SINGLE",        "CR-FGTS-07-01-single-01"),
    ("CR-FGTS-10-01-SINGLE",        "CR-FGTS-10-01-single-01"),
    ("CR-FGTS-12-01-SINGLE",        "CR-FGTS-12-01-single-01"),
    ("CR-FGTS-15-01-SINGLE",        "CR-FGTS-15-01-single-01"),
    ("CR-FGTS-23-01-SINGLE",        "CR-FGTS-23-01-single-01"),
    ("CR-FGTS-25-01-SINGLE",        "CR-FGTS-25-01-single-01"),
    ("CR-FGTS-08-01-SENIOR",        "CR-FGTS-08-01-senior-01"),
    ("CR-FGTS-08-02-MEZZANINE",     "CR-FGTS-08-02-mezzanine-02"),
    ("CR-FGTS-08-03-SUBORDINATED",  "CR-FGTS-08-03-subordinated-03"),
    ("CR-CONSORTIUMS-13-01-SINGLE", "CR-Consorcio-13-01-single-01"),
    ("CR-CONSORTIUMS-29-01-SINGLE", "CR-Consorcio-29-01-single-01"),
]

V2_SQL = """
SELECT v.date AS ts, v.date::date AS d, v.id,
       v.clean_price, COALESCE(v.accrued_interest,0) AS accrued,
       (v.clean_price + COALESCE(v.accrued_interest,0)) AS dirty, v.cash_flow
FROM valuations v
WHERE v.asset_id = (SELECT id FROM entities WHERE name = %s)
  AND v.methodology_id = (SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
ORDER BY v.date, v.id;
"""

V1_SQL = """
WITH s AS (SELECT aux_id FROM securities WHERE full_name = %s)
SELECT v.valuation_date AS d,
       v.value                                                           AS v1_value,
       (v.metadata->>'last_value')::numeric                              AS v1_last_value,
       (v.metadata->'amortization'->>'interest_payment')::numeric        AS v1_interest,
       (v.metadata->'amortization'->>'scheduled_repayment')::numeric     AS v1_scheduled,
       (v.metadata->'amortization'->>'extraordinary_repayment')::numeric AS v1_extra,
       (v.metadata ? 'amortization')                                     AS has_amort
FROM s JOIN valuations v ON v.aux_id = s.aux_id
ORDER BY v.valuation_date;
"""


def read_env():
    env = {}
    with open(os.path.join(HERE, ".env"), encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r"\s*([A-Z0-9_]+)\s*=\s*(.+?)\s*$", line)
            if m:
                env[m.group(1)] = m.group(2)
    v2, v1 = env.get("DATABASE_URL", ""), env.get("V1_DATABASE_URL", "")
    assert "127.0.0.1" in v2 and "/engine" in v2, f"V2 nao e' local/engine: {v2!r}"
    assert v1.startswith("postgres"), "V1_DATABASE_URL ausente/invalida"
    return v2, v1


def connect_ro(dsn):
    conn = psycopg2.connect(dsn)
    conn.set_session(readonly=True, autocommit=True)
    return conn


def f(x):
    return float(x) if isinstance(x, Decimal) else (None if x is None else float(x))


def fetch(conn, sql, param):
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, (param,))
        return [dict(r) for r in cur.fetchall()]


def prev_date_value(v1_dates, v1_by_date, d0):
    """value (PU pos) na ultima data V1 anterior a d0."""
    prev = [d for d in v1_dates if d < d0]
    if not prev:
        return None
    return f(v1_by_date[max(prev)]["v1_value"])


def v2_prev_eod_dirty(v2_rows, d0):
    """dirty da ultima linha V2 em dia anterior a d0 (EOD D-1)."""
    ant = [r for r in v2_rows if r["d"] < d0]
    if not ant:
        return None
    return f(ant[-1]["dirty"])  # v2_rows ja ordenado por ts,id


def main():
    v2_dsn, v1_dsn = read_env()
    c2, c1 = connect_ro(v2_dsn), connect_ro(v1_dsn)
    rows = []

    for v2_name, v1_name in PARES:
        v2_rows = fetch(c2, V2_SQL, v2_name)            # ordenado por ts,id
        v1_rows = fetch(c1, V1_SQL, v1_name)            # ordenado por d
        v1_by_date = {r["d"]: r for r in v1_rows}
        v1_dates = sorted(v1_by_date)

        # eventos V2 = cash_flow<>0; pula o 1o (compra), igual ao comparativo (ev_rn>1)
        ev = [r for r in v2_rows if r["cash_flow"] is not None and float(r["cash_flow"]) != 0.0]
        ev = ev[1:] if ev else []
        ev_by_date = {}
        for r in ev:
            ev_by_date.setdefault(r["d"], r)            # 1 evento por dia

        v2_event_dates = set(ev_by_date)
        v1_amort_dates = {r["d"] for r in v1_rows if r["has_amort"]}
        all_dates = sorted(v2_event_dates | v1_amort_dates)

        for d0 in all_dates:
            rec = {"serie": v2_name, "date": d0}

            # ---------- V1 ----------
            v1r = v1_by_date.get(d0)
            rec["p_Dm1_V1"] = prev_date_value(v1_dates, v1_by_date, d0)
            rec["p_D0_V1"] = f(v1r["v1_value"]) if v1r else None
            rec["p_D0ant_V1"] = f(v1r["v1_last_value"]) if (v1r and v1r["v1_last_value"] is not None) else None
            if v1r and v1r["has_amort"]:
                rec["juros_V1"] = (f(v1r["v1_interest"]) or 0) + (f(v1r["v1_scheduled"]) or 0) + (f(v1r["v1_extra"]) or 0)
            else:
                rec["juros_V1"] = None

            # ---------- V2 ----------
            evr = ev_by_date.get(d0)
            rec["p_Dm1_V2"] = v2_prev_eod_dirty(v2_rows, d0)
            if evr is not None:
                # horario anterior = ultima linha mesmo dia com ts < ts do evento
                same_day_before = [r for r in v2_rows if r["d"] == d0 and r["ts"] < evr["ts"]]
                ant = max(same_day_before, key=lambda r: r["ts"]) if same_day_before else None
                rec["p_D0ant_V2"] = f(ant["dirty"]) if ant else None
                rec["p_D0_V2"] = f(evr["dirty"])
                rec["juros_V2"] = (rec["p_D0ant_V2"] - rec["p_D0_V2"]) if ant else None
                rec["cash_flow_atual"] = f(evr["cash_flow"])
            else:
                # V2 NAO lancou evento neste dia (SO_V1) — mostra a diaria, juros V2 = 0
                same_day = [r for r in v2_rows if r["d"] == d0]
                rec["p_D0ant_V2"] = None
                rec["p_D0_V2"] = f(max(same_day, key=lambda r: r["ts"])["dirty"]) if same_day else None
                rec["juros_V2"] = 0.0 if same_day else None
                rec["cash_flow_atual"] = None

            # ---------- Bate? ----------
            jv1, jv2 = rec["juros_V1"], rec["juros_V2"]
            if jv1 is None or jv2 is None:
                rec["dif_V1_V2"] = None
                rec["bate"] = "N/A"
            else:
                rec["dif_V1_V2"] = jv1 - jv2
                rec["bate"] = "SIM" if abs(jv1 - jv2) < TOL else "NAO"

            rows.append(rec)

    df = pd.DataFrame(rows)
    cols = ["serie", "date",
            "p_Dm1_V1", "p_Dm1_V2", "p_D0_V1", "p_D0_V2", "p_D0ant_V2",
            "juros_V1", "juros_V2", "dif_V1_V2", "bate"]
    df = df[cols].sort_values(["serie", "date"]).reset_index(drop=True)

    out = os.path.join(HERE, "tabela_juros_v1_v2.csv")
    df.to_csv(out, index=False)

    pd.set_option("display.max_rows", None)
    pd.set_option("display.width", 260)
    pd.set_option("display.float_format", lambda x: f"{x:,.6f}")
    print(df.to_string(index=False))
    print("\n=== Bate? ===")
    print(df["bate"].value_counts().to_string())
    print(f"\nTotal de casos: {len(df)}  |  series: {df['serie'].nunique()}")
    print(f"CSV: {out}")


if __name__ == "__main__":
    main()
