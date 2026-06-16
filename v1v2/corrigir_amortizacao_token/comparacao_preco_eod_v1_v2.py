"""
Comparacao do PRECO DE FECHAMENTO (end-of-day) V2 local x V1, para TODAS as 17 series.

V2: ultimo timestamp do dia (clean_price + accrued_interest), methodology amortized_cost
    (o V2 tem ate 2 linhas/dia nos dias de evento; pega-se a de horario mais tarde).
V1: value (PU) diario (1 linha/dia).
Join por dia (datas comuns). Para cada serie: ate quando bate, onde/se descola, magnitude.

READ-ONLY nos dois bancos. Uma conexao V1 para todas as series (evita o limite do pooler).
"""
from __future__ import annotations
import os, re
from decimal import Decimal
import psycopg2, psycopg2.extras
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
TOL = 0.005  # PU; matches batem a ~3e-6, glitch ~0.058 -> separa limpo

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

V2_EOD_SQL = """
SELECT DISTINCT ON (v.date::date) v.date::date AS d,
       (v.clean_price + COALESCE(v.accrued_interest,0)) AS v2_eod
FROM valuations v
WHERE v.asset_id = (SELECT id FROM entities WHERE name = %s)
  AND v.methodology_id = (SELECT id FROM valuation_methodologies WHERE name = 'amortized_cost')
ORDER BY v.date::date, v.date DESC, v.id DESC;
"""

V1_PU_SQL = """
WITH s AS (SELECT aux_id FROM securities WHERE full_name = %s)
SELECT DISTINCT ON (v.valuation_date) v.valuation_date AS d, v.value AS v1
FROM s JOIN valuations v ON v.aux_id = s.aux_id
WHERE v.type = 'pu'
ORDER BY v.valuation_date, v.id DESC;
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
    assert v1.startswith("postgres"), "V1_DATABASE_URL ausente"
    return v2, v1


def connect_ro(dsn):
    conn = psycopg2.connect(dsn)
    conn.set_session(readonly=True, autocommit=True)
    return conn


def fetch(conn, sql, param):
    with conn.cursor() as cur:
        cur.execute(sql, (param,))
        return {r[0]: float(r[1]) for r in cur.fetchall() if r[1] is not None}


def main():
    v2_dsn, v1_dsn = read_env()
    c2, c1 = connect_ro(v2_dsn), connect_ro(v1_dsn)

    resumo, detalhe = [], []
    for v2_name, v1_name in PARES:
        v2 = fetch(c2, V2_EOD_SQL, v2_name)
        v1 = fetch(c1, V1_PU_SQL, v1_name)
        dias = sorted(set(v2) & set(v1))
        difs = [(d, v2[d] - v1[d]) for d in dias]
        for d, dl in difs:
            detalhe.append({"serie": v2_name, "dia": d, "v2_eod": v2[d], "v1": v1[d], "delta": dl})
        if not difs:
            resumo.append({"serie": v2_name, "dias_comuns": 0, "veredito": "SEM DADO COMUM"})
            continue
        fora = [(d, dl) for d, dl in difs if abs(dl) > TOL]
        n_match = len(difs) - len(fora)
        ult_d, ult_dl = difs[-1]
        row = {
            "serie": v2_name,
            "dias_comuns": len(difs),
            "n_bate": n_match,
            "n_descola": len(fora),
            "periodo": f"{dias[0]} a {dias[-1]}",
            "delta_max_abs": round(max(abs(dl) for _, dl in difs), 6),
            "delta_ultimo_dia": round(ult_dl, 6),
        }
        if fora:
            d0, dl0 = fora[0]
            row["veredito"] = f"DESCOLA em {d0} (delta {dl0:+.4f})"
        else:
            row["veredito"] = "BATE SEMPRE"
        resumo.append(row)

    df = pd.DataFrame(resumo)
    dd = pd.DataFrame(detalhe)
    out = os.path.join(HERE, "comparacao_preco_eod_v1_v2.csv")
    dd.to_csv(out, index=False)

    pd.set_option("display.width", 240)
    pd.set_option("display.max_rows", None)
    pd.set_option("display.float_format", lambda x: f"{x:,.6f}")
    cols = ["serie", "dias_comuns", "n_bate", "n_descola", "periodo",
            "delta_max_abs", "delta_ultimo_dia", "veredito"]
    print(df[[c for c in cols if c in df.columns]].to_string(index=False))
    print(f"\nDetalhe diario ({len(dd)} linhas) -> {out}")


if __name__ == "__main__":
    main()
