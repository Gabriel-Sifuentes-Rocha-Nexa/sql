"""grafico_cons29.py — plota dirty EOD V1 x V2 do CONS-29. READ-ONLY. Salva PNG."""
import os, re
import psycopg2
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

HERE = os.path.dirname(os.path.abspath(__file__))
def read_env(p):
    e = {}
    with open(p, encoding="utf-8") as fh:
        for ln in fh:
            m = re.match(r"\s*([A-Z0-9_]+)\s*=\s*(.+?)\s*$", ln)
            if m: e[m.group(1)] = m.group(2).strip().strip('"').strip("\r")
    return e
V2 = read_env(os.path.join(HERE, "..", "queries", ".env"))["DATABASE_URL"]
V1 = read_env(os.path.join(HERE, ".env"))["V1_DATABASE_URL"]

def ro(dsn):
    c = psycopg2.connect(dsn); c.set_session(readonly=True, autocommit=True); return c
c2, c1 = ro(V2), ro(V1)
def q(c, sql, p):
    with c.cursor() as cur: cur.execute(sql, (p,)); return cur.fetchall()

V2_SQL = """SELECT v.date::date d, (v.clean_price+COALESCE(v.accrued_interest,0))::float dirty
FROM valuations v WHERE v.asset_id=1058821
AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
AND v.date>=timestamptz '2026-04-15 00:00:00-03' ORDER BY v.date;"""
V1_SQL = """WITH s AS (SELECT aux_id FROM securities WHERE full_name=%s)
SELECT v.valuation_date d, v.value::float FROM s JOIN valuations v ON v.aux_id=s.aux_id
WHERE v.valuation_date>=DATE '2026-04-15' ORDER BY v.valuation_date;"""

eod2 = {}
for d, dirty in q(c2, V2_SQL, None) if False else []:
    pass
with c2.cursor() as cur:
    cur.execute(V2_SQL);
    for d, dirty in cur.fetchall(): eod2[d] = dirty   # EOD = ultima linha do dia
v1 = {d: val for d, val in q(c1, V1_SQL, "CR-Consorcio-29-01-single-01")}

d2 = sorted(eod2); y2 = [eod2[d] for d in d2]
d1 = sorted(v1);   y1 = [v1[d] for d in d1]
amorts = {  # data: (label, juros/un)
    "2026-05-05": "amort 63.26", "2026-05-15": "amort 14.76",
    "2026-06-03": "amort 1.88", "2026-06-09": "amort 9.92", "2026-06-12": "amort 10.16",
}

fig, ax = plt.subplots(figsize=(12, 6))
ax.plot(d1, y1, "-o", ms=4, lw=1.6, color="#1f77b4", label="V1 (dirty, fonte de verdade)")
ax.plot(d2, y2, "-s", ms=3, lw=1.2, color="#d62728", alpha=0.8, label="V2 (clean+accrued, EOD)")
import datetime
for ds, lab in amorts.items():
    dt = datetime.date.fromisoformat(ds)
    ax.axvline(dt, color="gray", ls="--", lw=0.7, alpha=0.6)
    ax.annotate(lab, xy=(dt, ax.get_ylim()[1]), fontsize=7, rotation=90,
                va="top", ha="right", color="gray")
ax.set_title("CR-CONSORTIUMS-29 — preço dirty V1 x V2 (amortizante, vence 2026-06-15)")
ax.set_ylabel("dirty (clean + accrued)"); ax.set_xlabel("data")
ax.xaxis.set_major_formatter(mdates.DateFormatter("%m-%d"))
ax.xaxis.set_major_locator(mdates.DayLocator(interval=7))
ax.grid(True, alpha=0.25); ax.legend(loc="upper right")
fig.autofmt_xdate(); fig.tight_layout()
out = os.path.join(HERE, "grafico_cons29.png")
fig.savefig(out, dpi=130)
print("salvo:", out)
print(f"V2 ultima: {d2[-1]} = {y2[-1]:.6f} | V1 ultima: {d1[-1]} = {y1[-1]:.6f} | diff = {y2[-1]-y1[-1]:+.5f}")
