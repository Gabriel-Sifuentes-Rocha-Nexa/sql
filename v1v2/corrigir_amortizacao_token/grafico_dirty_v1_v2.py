"""
grafico_dirty_v1_v2.py
---------------------------------------------------------------------------------------
Plota o DIRTY price (clean + accrued) ao longo do tempo, V1 (Supabase prod) x V2 (PROD,
tunel :5003), para os CRs que precisam de intuicao de correcao:
  - CR-FGTS-25  (JA CORRIGIDO -> referencia de "como fica quando bate")
  - CR-FGTS-23  (gap de accrual ~0.49 desde a emissao)
  - CR-FGTS-08-01-SENIOR  / CR-FGTS-08-02-MEZZANINE (vencimento lumped)

READ-ONLY nos dois bancos. V2 dirty = clean_price + accrued_interest (metodologia
amortized_cost). V1 dirty = valuations.value (PU). Salva PNG nesta pasta.
"""
from __future__ import annotations
import os, re
import psycopg2, psycopg2.extras
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))

# V2 PROD em ../queries/.env (tunel 5003); V1 nesta pasta (.env -> V1_DATABASE_URL)
def read_env(path):
    env = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r"\s*([A-Z0-9_]+)\s*=\s*(.+?)\s*$", line)
            if m:
                env[m.group(1)] = m.group(2).strip().strip('"').strip("\r")
    return env

q_env = read_env(os.path.join(HERE, "..", "queries", ".env"))
c_env = read_env(os.path.join(HERE, ".env"))
V2_DSN = q_env["DATABASE_URL"]               # PROD tunel 5003
V1_DSN = c_env["V1_DATABASE_URL"]            # V1 Supabase prod
assert ":5003" in V2_DSN, f"V2 nao e' o tunel PROD :5003 -> {V2_DSN.split('@')[-1]}"

TARGETS = [
    ("CR-FGTS-25-01-SINGLE",    "CR-FGTS-25-01-single-01",     "FGTS-25  (JA CORRIGIDO - referencia)"),
    ("CR-FGTS-23-01-SINGLE",    "CR-FGTS-23-01-single-01",     "FGTS-23  (gap de accrual)"),
    ("CR-FGTS-08-01-SENIOR",    "CR-FGTS-08-01-senior-01",     "FGTS-08-01 SENIOR (vencimento)"),
    ("CR-FGTS-08-02-MEZZANINE", "CR-FGTS-08-02-mezzanine-02",  "FGTS-08-02 MEZZANINE (vencimento)"),
]

V2_SQL = """
SELECT v.date AS ts, (v.clean_price + COALESCE(v.accrued_interest,0)) AS dirty
FROM valuations v
WHERE v.asset_id = (SELECT id FROM entities WHERE name=%s)
  AND v.methodology_id = (SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date >= timestamptz '2026-02-01 00:00:00-03'
ORDER BY v.date;
"""
V1_SQL = """
WITH s AS (SELECT aux_id FROM securities WHERE full_name=%s)
SELECT v.valuation_date AS d, v.value AS dirty
FROM s JOIN valuations v ON v.aux_id=s.aux_id
WHERE v.valuation_date >= DATE '2026-02-01'
ORDER BY v.valuation_date;
"""

def connect_ro(dsn):
    c = psycopg2.connect(dsn)
    c.set_session(readonly=True, autocommit=True)
    return c

def fetch(conn, sql, p):
    with conn.cursor() as cur:
        cur.execute(sql, (p,))
        return cur.fetchall()

def main():
    c2, c1 = connect_ro(V2_DSN), connect_ro(V1_DSN)
    fig, axes = plt.subplots(2, 2, figsize=(15, 9))
    axes = axes.ravel()
    for ax, (v2name, v1name, title) in zip(axes, TARGETS):
        v2 = fetch(c2, V2_SQL, v2name)
        v1 = fetch(c1, V1_SQL, v1name)
        if v2:
            x2 = pd.to_datetime([r[0] for r in v2]); y2 = [float(r[1]) for r in v2]
            ax.plot(x2, y2, color="tab:red", lw=1.4, label=f"V2 (PROD) n={len(v2)}")
        if v1:
            x1 = pd.to_datetime([r[0] for r in v1]); y1 = [float(r[1]) for r in v1]
            ax.plot(x1, y1, color="tab:blue", lw=1.4, ls="--", label=f"V1 (Supabase) n={len(v1)}")
        ax.set_title(title, fontsize=11)
        ax.set_ylabel("dirty (clean+accrued)")
        ax.grid(alpha=0.3); ax.legend(fontsize=8)
        ax.tick_params(axis="x", labelrotation=30, labelsize=8)
    fig.suptitle("Dirty price V1 x V2 ao longo do tempo (2026)", fontsize=13)
    fig.tight_layout(rect=[0, 0, 1, 0.97])
    out = os.path.join(HERE, "grafico_dirty_v1_v2.png")
    fig.savefig(out, dpi=130)
    print("PNG:", out)

if __name__ == "__main__":
    main()
