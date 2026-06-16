"""
compara_dirty_v1_v2.py  — quantifica o descolamento V1 x V2 (dirty EOD) dia-a-dia.
READ-ONLY. V2 PROD (tunel 5003) em ../queries/.env; V1 Supabase em ./.env (V1_DATABASE_URL).
Para cada CR: range, datas casadas, max|diff|, 1a data onde |diff|>0.05 (descolamento),
e cobertura (datas que o V1 tem e o V2 nao, e vice-versa).
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

TARGETS = [
    ("CR-CONSORTIUMS-29-01-SINGLE", "CR-Consorcio-29-01-single-01"),
    ("CR-CONSORTIUMS-40-01-SINGLE", "CR-Consorcio-40-01-single-01"),
    ("CR-FGTS-25-01-SINGLE",        "CR-FGTS-25-01-single-01"),
    ("CR-FGTS-32-01-SINGLE",        "CR-FGTS-32-01-single-01"),
    ("CR-FGTS-34-01-SINGLE",        "CR-FGTS-34-01-single-01"),
]
V2_SQL = """SELECT v.date::date d, (v.clean_price+COALESCE(v.accrued_interest,0))::float dirty, v.date ts
FROM valuations v WHERE v.asset_id=(SELECT id FROM entities WHERE name=%s)
AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
AND v.date>=timestamptz '2026-02-01 00:00:00-03' ORDER BY v.date;"""
V1_SQL = """WITH s AS (SELECT aux_id FROM securities WHERE full_name=%s)
SELECT v.valuation_date d, v.value::float dirty FROM s JOIN valuations v ON v.aux_id=s.aux_id
WHERE v.valuation_date>=DATE '2026-02-01' ORDER BY v.valuation_date;"""

def ro(dsn):
    c = psycopg2.connect(dsn); c.set_session(readonly=True, autocommit=True); return c
c2, c1 = ro(V2), ro(V1)
def q(c, sql, p):
    with c.cursor() as cur: cur.execute(sql, (p,)); return cur.fetchall()

for v2n, v1n in TARGETS:
    r2 = q(c2, V2_SQL, v2n); r1 = q(c1, V1_SQL, v1n)
    eod2 = {}                       # EOD V2 (ultima linha do dia)
    for d, dirty, ts in r2: eod2[d] = dirty
    eod1 = {d: dirty for d, dirty in r1}
    common = sorted(set(eod1) & set(eod2))
    diffs = [(d, eod2[d]-eod1[d]) for d in common]
    only1 = sorted(set(eod1) - set(eod2))   # V1 tem, V2 nao
    only2 = sorted(set(eod2) - set(eod1))   # V2 tem, V1 nao
    print(f"\n=== {v2n} ===")
    print(f"  V2 datas={len(eod2)} ({min(eod2)}..{max(eod2)}) | V1 datas={len(eod1)} ({min(eod1)}..{max(eod1)})")
    if diffs:
        mx = max(diffs, key=lambda t: abs(t[1]))
        print(f"  casadas={len(common)}  max|V2-V1|={mx[1]:+.4f} em {mx[0]}")
        desc = [d for d, df in diffs if abs(df) > 0.05]
        print(f"  1a data |diff|>0.05: {desc[0] if desc else 'nenhuma'}   (total {len(desc)} datas descoladas)")
    print(f"  datas SO no V1 (V2 nao tem): {len(only1)}" + (f"  ex: {only1[:5]}" if only1 else ""))
    print(f"  datas SO no V2 (V1 nao tem): {len(only2)}" + (f"  ex: {only2[:5]}" if only2 else ""))
