"""Dump completo da serie de valuations de NXCOB26-4 no V1 (READ-ONLY)."""
import os, psycopg2
DSN = os.environ["DATABASE_URL"]
SQL = """
WITH s AS (SELECT aux_id FROM securities WHERE full_name='NXCOB26-4')
SELECT v.valuation_date::date d, v.value::float val, v.type,
       v.metadata->>'amortization' amort, v.metadata
FROM s JOIN valuations v ON v.aux_id = s.aux_id
ORDER BY v.valuation_date;
"""
c = psycopg2.connect(DSN); c.set_session(readonly=True, autocommit=True)
with c.cursor() as cur:
    cur.execute(SQL); rows = cur.fetchall()
c.close()
prev=None
print(f"{'date':<12}{'value':>16}{'d/d%':>10}  type")
for d,val,typ,amort,meta in rows:
    chg = "" if prev is None or prev==0 else f"{(val/prev-1)*100:>9.3f}"
    mark = "  <== NEGATIVO" if val < 0 else ""
    print(f"{str(d):<12}{val:>16.4f}{chg:>10}  {typ}{mark}")
    prev=val
# mostra metadata das datas-chave (1a, a da queda, 1a negativa, ultima)
print("\n--- metadata de datas-chave ---")
neg=[r for r in rows if r[1]<0]
keys=[rows[0], rows[-1]] + ([neg[0]] if neg else [])
for d,val,typ,amort,meta in keys:
    print(f"\n[{d}] value={val} type={typ}\n  {meta}")
