"""
Comparacao CASO A CASO do cash_flow de eventos de securitization_series: V2 (local)
x V1 (Supabase, fonte-de-verdade da metadata `amortization`).

READ-ONLY nos dois bancos. V2 local (127.0.0.1/engine); V1 prod (so SELECT, sessao
read-only). Nao escreve nada. Le as URLs do .env desta pasta (DATABASE_URL, V1_DATABASE_URL).

Para cada evento (linha de valuations com cash_flow<>0, exceto a compra/1o evento):
  V2: clean/accrued antes e depois, queda do clean (principal), queda do accrued
      (detector de glitch), queda do dirty (= a correcao atual), cash_flow atual (errado).
  V1: last_value, value, e o objeto amortization (interest_payment / scheduled /
      extraordinary) -> total = a grandeza-verdade do caixa.
  Join por (serie, data). Veredito por caso.

Saida: console + CSV (comparacao_cash_flow_v1_v2.csv) nesta pasta.
"""
from __future__ import annotations
import os, re, sys
from decimal import Decimal
import psycopg2, psycopg2.extras
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
TOL = 0.001  # tolerancia de match (em PU). matches batem a ~1e-6; erros ~0.058.

# V2 name -> V1 full_name (do recon 2026-06-09, mapeamento 1:1 confirmado)
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
WITH base AS (
  SELECT v.date, v.id, v.clean_price, v.accrued_interest, v.cash_flow,
         (v.clean_price + COALESCE(v.accrued_interest,0)) AS dirty,
         LAG(v.clean_price)                                  OVER w AS clean_before,
         LAG(COALESCE(v.accrued_interest,0))                 OVER w AS accrued_before,
         LAG(v.clean_price + COALESCE(v.accrued_interest,0)) OVER w AS dirty_before
  FROM valuations v
  WHERE v.asset_id = (SELECT id FROM entities WHERE name = %s)
  WINDOW w AS (PARTITION BY v.asset_id, v.methodology_id, v.lot_id ORDER BY v.date, v.id)
),
ev AS (
  SELECT *, ROW_NUMBER() OVER (ORDER BY date, id) AS ev_rn
  FROM base WHERE cash_flow IS NOT NULL AND cash_flow <> 0
)
SELECT date::date AS date,
       clean_before, clean_price AS clean_after,
       accrued_before, COALESCE(accrued_interest,0) AS accrued_after,
       dirty_before, dirty AS dirty_after, cash_flow
FROM ev WHERE ev_rn > 1 ORDER BY date;
"""

V1_SQL = """
WITH s AS (SELECT aux_id FROM securities WHERE full_name = %s)
SELECT v.valuation_date AS date,
       (v.metadata->>'last_value')::numeric                              AS v1_last_value,
       v.value                                                           AS v1_value,
       (v.metadata->'amortization'->>'interest_payment')::numeric        AS v1_interest,
       (v.metadata->'amortization'->>'scheduled_repayment')::numeric     AS v1_scheduled,
       (v.metadata->'amortization'->>'extraordinary_repayment')::numeric AS v1_extra
FROM s JOIN valuations v ON v.aux_id = s.aux_id
WHERE v.metadata ? 'amortization'
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


def verdict(row):
    if pd.isna(row["v1_total"]):
        return "SO_V2 (V1 sem evento)"
    if pd.isna(row["cash_flow_atual"]):
        return "SO_V1 (V2 nao lancou)"
    dc, dd = row["d_clean"], row["d_dirty"]
    ok_c, ok_d = abs(dc) < TOL, abs(dd) < TOL
    if ok_c and ok_d:
        return "OK (clean=dirty=V1)"
    if ok_c and not ok_d:
        return "GLITCH_ACCRUED (clean=V1, dirty contaminado)"
    if ok_d and not ok_c:
        return "CUPOM_PAGO (dirty=V1)"
    return "DIVERGE (investigar)"


def main():
    v2_dsn, v1_dsn = read_env()
    c2, c1 = connect_ro(v2_dsn), connect_ro(v1_dsn)
    rows = []
    for v2_name, v1_name in PARES:
        v2 = {r["date"]: r for r in fetch(c2, V2_SQL, v2_name)}
        v1 = {r["date"]: r for r in fetch(c1, V1_SQL, v1_name)}
        for d in sorted(set(v2) | set(v1)):
            a, b = v2.get(d), v1.get(d)
            rec = {"serie": v2_name, "date": d}
            if a:
                cb, ca = f(a["clean_before"]), f(a["clean_after"])
                ab, aa = f(a["accrued_before"]), f(a["accrued_after"])
                rec.update(
                    clean_before=cb, clean_after=ca,
                    clean_drop=(cb - ca) if cb is not None else None,
                    accrued_drop=(ab - aa) if ab is not None else None,
                    dirty_drop=f(a["dirty_before"]) - f(a["dirty_after"]) if a["dirty_before"] is not None else None,
                    cash_flow_atual=f(a["cash_flow"]),
                )
            if b:
                tot = (f(b["v1_interest"]) or 0) + (f(b["v1_scheduled"]) or 0) + (f(b["v1_extra"]) or 0)
                rec.update(
                    v1_interest=f(b["v1_interest"]), v1_scheduled=f(b["v1_scheduled"]),
                    v1_extra=f(b["v1_extra"]), v1_total=tot, v1_value=f(b["v1_value"]),
                )
                if a and rec.get("dirty_after") is None:
                    rec["dirty_after"] = f(a["dirty_after"])
            rows.append(rec)

    df = pd.DataFrame(rows)
    for col in ["clean_drop", "dirty_drop", "v1_total"]:
        if col not in df:
            df[col] = pd.NA
    df["d_clean"] = df["clean_drop"] - df["v1_total"]
    df["d_dirty"] = df["dirty_drop"] - df["v1_total"]
    # preco V2 (dirty depois) x V1 value, na data do evento
    da = df["serie"].map(lambda s: None)  # placeholder
    df["price_off_v2_minus_v1"] = [
        (f(a) - v) if (a is not None and v is not None) else None
        for a, v in zip(df.get("dirty_after"), df.get("v1_value"))
    ] if "dirty_after" in df and "v1_value" in df else None
    df["veredito"] = df.apply(verdict, axis=1)

    cols = ["serie", "date", "clean_before", "clean_after", "clean_drop", "accrued_drop",
            "dirty_drop", "cash_flow_atual", "v1_interest", "v1_extra", "v1_total",
            "d_clean", "d_dirty", "price_off_v2_minus_v1", "veredito"]
    cols = [c for c in cols if c in df.columns]
    df = df[cols].sort_values(["serie", "date"]).reset_index(drop=True)

    out = os.path.join(HERE, "comparacao_cash_flow_v1_v2.csv")
    df.to_csv(out, index=False)

    pd.set_option("display.max_rows", None)
    pd.set_option("display.width", 240)
    pd.set_option("display.float_format", lambda x: f"{x:,.6f}")
    print(df.to_string(index=False))
    print("\n=== RESUMO POR VEREDITO ===")
    print(df["veredito"].value_counts().to_string())
    print(f"\nTotal de casos: {len(df)}  |  series: {df['serie'].nunique()}")
    print(f"CSV: {out}")


if __name__ == "__main__":
    main()
