"""
diag_fgts08_v1_v2.py — diagnostico dia-a-dia V1 x V2 das 3 tranches do CR-FGTS-08.
READ-ONLY. V2 PROD (tunel 5003) em ../queries/.env; V1 Supabase em ./.env.
Para cada tranche imprime:
  - 1a data de divergencia (|dirty V2 - value V1| > 0.02)
  - todos os eventos: V1 drop>0.3 (amort/redemption) e V2 cash_flow<>0
  - janela compacta em volta de cada evento + cauda
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
    ("08-01-SENIOR",       "CR-FGTS-08-01-SENIOR",       "CR-FGTS-08-01-senior-01"),
    ("08-02-MEZZANINE",    "CR-FGTS-08-02-MEZZANINE",    "CR-FGTS-08-02-mezzanine-02"),
    ("08-03-SUBORDINATED", "CR-FGTS-08-03-SUBORDINATED", "CR-FGTS-08-03-subordinated-03"),
]
V2_SQL = """SELECT v.date::date d, v.clean_price::float clean, COALESCE(v.accrued_interest,0)::float acc,
       (v.clean_price+COALESCE(v.accrued_interest,0))::float dirty, COALESCE(v.cash_flow,0)::float cf
FROM valuations v WHERE v.asset_id=(SELECT id FROM entities WHERE name=%s)
AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
ORDER BY v.date;"""
V1_SQL = """WITH s AS (SELECT aux_id FROM securities WHERE full_name=%s)
SELECT v.valuation_date d, v.value::float dirty FROM s JOIN valuations v ON v.aux_id=s.aux_id
ORDER BY v.valuation_date;"""

def ro(dsn):
    c = psycopg2.connect(dsn); c.set_session(readonly=True, autocommit=True); return c
c2, c1 = ro(V2), ro(V1)
def q(c, sql, p):
    with c.cursor() as cur: cur.execute(sql, (p,)); return cur.fetchall()

for tag, v2n, v1n in TARGETS:
    rows2 = q(c2, V2_SQL, v2n)
    eod, cfday = {}, {}
    for d, clean, acc, dirty, cf in rows2:
        eod[d] = (clean, acc, dirty)
        if abs(cf) > 1e-9: cfday[d] = cf
    v1 = {d: dirty for d, dirty in q(c1, V1_SQL, v1n)}
    common = sorted(set(eod) & set(v1))
    print(f"\n############### {tag}  ({v2n}) ###############")
    print(f"  V2 {min(eod)}..{max(eod)} ({len(eod)}d)  |  V1 {min(v1)}..{max(v1)} ({len(v1)}d)  |  comuns={len(common)}")
    # 1a divergencia
    first_div = next((d for d in common if abs(eod[d][2]-v1[d]) > 0.02), None)
    print(f"  >>> 1a divergencia (|dirty diff|>0.02): {first_div}")
    # eventos V1 (drop>0.3) e V2 (cf<>0)
    v1d_sorted = sorted(v1)
    v1_events, prev = [], None
    for d in v1d_sorted:
        if prev is not None and (v1[prev]-v1[d]) > 0.3:
            v1_events.append((d, v1[prev]-v1[d]))
        prev = d
    print(f"  V1 eventos (drop>0.3): {[(str(d),round(x,4)) for d,x in v1_events]}")
    print(f"  V2 cash_flow events:   {[(str(d),round(cfday[d],4)) for d in sorted(cfday)]}")
    # datas a mostrar: vizinhanca de cada evento (V1 e V2) + 1a div + cauda
    interest = set()
    for d,_ in v1_events: interest.add(d)
    interest |= set(cfday)
    if first_div: interest.add(first_div)
    show = set()
    alld = sorted(set(eod)|set(v1))
    idx = {d:i for i,d in enumerate(alld)}
    for d in interest:
        i = idx[d]
        for j in range(max(0,i-2), min(len(alld),i+3)): show.add(alld[j])
    show |= set(alld[-4:])
    print(f"  {'date':<12}{'V1_val':>13}{'V2_clean':>12}{'V2_accr':>12}{'V2_dirty':>13}{'diff':>11}{'V2_cf':>13}")
    for d in sorted(show):
        v1v = v1.get(d); e = eod.get(d)
        v1s = f"{v1v:>13.6f}" if v1v is not None else f"{'-':>13}"
        if e:
            clean, acc, dirty = e
            diff = (dirty-v1v) if v1v is not None else float('nan')
            diffs = f"{diff:>11.5f}" if v1v is not None else f"{'-':>11}"
            cfs = f"{cfday[d]:>13.5f}" if d in cfday else f"{'':>13}"
            print(f"  {str(d):<12}{v1s}{clean:>12.5f}{acc:>12.5f}{dirty:>13.5f}{diffs}{cfs}")
        else:
            print(f"  {str(d):<12}{v1s}{'-':>12}{'-':>12}{'-':>13}{'-':>11}{'':>13}")
