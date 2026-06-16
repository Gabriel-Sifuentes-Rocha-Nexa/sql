"""
compara_inicio_accrual_v1_v2.py — 1o dia de accrual (accrued>0) por CR FGTS, V1 x V2.
READ-ONLY. Casa os nomes pela chave 'CR-FGTS-{n}-{seq}' (4 primeiros componentes).
V2: min(date) com accrued_interest>0 (amortized_cost). V1: min(valuation_date) com value>100.
"""
import os, re
import psycopg2

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

def key(name):  # 'CR-FGTS-23-01-SINGLE' / 'CR-FGTS-23-01-single-01' -> 'CR-FGTS-23-01'
    return "-".join(name.upper().split("-")[:4])

# V2
with c2.cursor() as cur:
    cur.execute("""
      SELECT e.name, ss.issuance_date,
        (SELECT min(v.date)::date FROM valuations v
          WHERE v.asset_id=ss.id
            AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
            AND v.accrued_interest>0)
      FROM securitization_series ss JOIN entities e ON e.id=ss.id
      WHERE e.name LIKE 'CR-FGTS-%';
    """)
    v2 = {}
    for name, iss, start in cur.fetchall():
        v2[key(name)] = {"name": name, "iss": iss, "start": start}

# V1
with c1.cursor() as cur:
    cur.execute("""
      SELECT s.full_name, min(v.valuation_date)
      FROM securities s JOIN valuations v ON v.aux_id=s.aux_id
      WHERE s.type='spv_series' AND s.full_name ILIKE 'CR-FGTS-%' AND v.value>100
      GROUP BY s.full_name;
    """)
    v1 = {}
    for fn, start in cur.fetchall():
        v1[key(fn)] = {"fn": fn, "start": start}

keys = sorted(set(v2) | set(v1), key=lambda k: (v2.get(k, {}).get("iss") or v1.get(k, {}).get("start") or __import__("datetime").date(2000,1,1), k))
print(f"{'CR':<16}{'emissao':>12}{'V2_start':>12}{'V1_start':>12}{'shift(V1-V2)':>14}")
for k in keys:
    a = v2.get(k, {}); b = v1.get(k, {})
    iss = a.get("iss"); s2 = a.get("start"); s1 = b.get("start")
    shift = (s1 - s2).days if (s1 and s2) else None
    print(f"{k:<16}{str(iss or '-'):>12}{str(s2 or '-'):>12}{str(s1 or '-'):>12}{(str(shift)+'d' if shift is not None else '-'):>14}")
