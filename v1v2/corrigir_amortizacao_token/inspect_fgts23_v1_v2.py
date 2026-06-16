"""
inspect_fgts23_v1_v2.py — detalhe dia-a-dia FGTS-23, V1 x V2. READ-ONLY nos dois.
Objetivo: achar (a) onde V2 comeca a descolar do V1 (descolamento fino), (b) janela do
freeze de accrued, (c) o salto do amort 05-07. Imprime: data, V2 clean/accrued/dirty,
V1 dirty, diff dirty, e flag de freeze (accrued nao mudou vs dia anterior).
V2 PROD (tunel 5003) em ../queries/.env; V1 Supabase em ./.env (V1_DATABASE_URL).
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

V2N, V1N = "CR-FGTS-23-01-SINGLE", "CR-FGTS-23-01-single-01"
V2_SQL = """SELECT v.date::date d, v.clean_price::float clean, COALESCE(v.accrued_interest,0)::float acc,
       (v.clean_price+COALESCE(v.accrued_interest,0))::float dirty, v.cash_flow::float cf, v.date ts
FROM valuations v WHERE v.asset_id=(SELECT id FROM entities WHERE name=%s)
AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
AND v.date>=timestamptz '2026-02-13 00:00:00-03' ORDER BY v.date;"""
V1_SQL = """WITH s AS (SELECT aux_id FROM securities WHERE full_name=%s)
SELECT v.valuation_date d, v.value::float dirty FROM s JOIN valuations v ON v.aux_id=s.aux_id
WHERE v.valuation_date>=DATE '2026-02-13' ORDER BY v.valuation_date;"""

def ro(dsn):
    c = psycopg2.connect(dsn); c.set_session(readonly=True, autocommit=True); return c
c2, c1 = ro(V2), ro(V1)
def q(c, sql, p):
    with c.cursor() as cur: cur.execute(sql, (p,)); return cur.fetchall()

# V2: EOD (ultima linha do dia) -> clean/accrued/dirty; tb guarda eventos (cf<>0)
rows2 = q(c2, V2_SQL, V2N)
eod = {}
events = []
for d, clean, acc, dirty, cf, ts in rows2:
    eod[d] = (clean, acc, dirty)
    if abs(cf) > 1e-9 and d > __import__("datetime").date(2026, 2, 13):
        events.append((d, clean, acc, cf))
v1 = {d: dirty for d, dirty in q(c1, V1_SQL, V1N)}

print(f"{'date':<12}{'V2_clean':>13}{'V2_accr':>12}{'V2_dirty':>13}{'V1_dirty':>13}{'diff':>10}  flag")
prev_acc = None
for d in sorted(eod):
    clean, acc, dirty = eod[d]
    v1d = v1.get(d)
    diff = (dirty - v1d) if v1d is not None else None
    flag = ""
    if prev_acc is not None and abs(acc - prev_acc) < 1e-9:
        flag += "FREEZE "          # accrued nao mudou vs dia anterior
    if v1d is not None and abs(diff) > 0.01:
        flag += f"DESCOLA"
    v1s = f"{v1d:>13.6f}" if v1d is not None else f"{'(esparso)':>13}"
    diffs = f"{diff:>10.5f}" if diff is not None else f"{'-':>10}"
    print(f"{str(d):<12}{clean:>13.6f}{acc:>12.6f}{dirty:>13.6f}{v1s}{diffs}  {flag}")
    prev_acc = acc

print("\n--- EVENTOS V2 (cash_flow<>0, exceto emissao 02-13) ---")
for d, clean, acc, cf in events:
    print(f"  {d}  clean={clean:.6f}  accrued={acc:.6f}  cash_flow={cf:.6f}")

print("\n--- AMORTS V1 (metadata amortization) ---")
V1_AM = """WITH s AS (SELECT aux_id FROM securities WHERE full_name=%s)
SELECT (a->>'date')::date dt,
       COALESCE((a->>'interest_payment')::float,0)+COALESCE((a->>'scheduled')::float,0)+COALESCE((a->>'extraordinary')::float,0) juros
FROM s JOIN securities sec ON sec.aux_id=s.aux_id,
     jsonb_array_elements(sec.metadata->'amortization') a
WHERE (a->>'date')::date >= DATE '2026-02-14' ORDER BY 1;"""
try:
    for dt, juros in q(c1, V1_AM, V1N):
        print(f"  {dt}  juros={juros:.8f}")
except Exception as e:
    print("  (nao consegui ler metadata->amortization:", e, ")")
