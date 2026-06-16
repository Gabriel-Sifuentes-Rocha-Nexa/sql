"""
diag_precos_v1_v2.py — diagnostico dia-a-dia V1 x V2 p/ os CRs reportados com preco errado.
READ-ONLY nos dois. V2 PROD (tunel 5003) em ../queries/.env; V1 Supabase em ./.env.
Para cada CR (serie): imprime as datas COMUNS (dias uteis casados) com V1 value, V2 clean/
accrued/dirty, diff(V2-V1), e flags:
  AMORT_V1 = V1 caiu >0.5 vs ultima obs V1 (amortizou)   |  CF_V2 = V2 teve cash_flow<>0 no dia
  DESCOLA  = |diff|>0.02
Mostra so' a janela relevante: as ultimas N datas + qualquer data com flag/descolamento.
"""
import os, re, datetime
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
    ("CONS-29", "CR-CONSORTIUMS-29-01-SINGLE", "CR-Consorcio-29-01-single-01"),
    ("CONS-40", "CR-CONSORTIUMS-40-01-SINGLE", "CR-Consorcio-40-01-single-01"),
    ("FGTS-25", "CR-FGTS-25-01-SINGLE",        "CR-FGTS-25-01-single-01"),
    ("FGTS-32", "CR-FGTS-32-01-SINGLE",        "CR-FGTS-32-01-single-01"),
    ("FGTS-34", "CR-FGTS-34-01-SINGLE",        "CR-FGTS-34-01-single-01"),
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
        eod[d] = (clean, acc, dirty)            # ultima linha do dia (EOD)
        if abs(cf) > 1e-9: cfday[d] = cf
    v1 = {d: dirty for d, dirty in q(c1, V1_SQL, v1n)}
    common = sorted(set(eod) & set(v1))
    if not common:
        print(f"\n########## {tag} :: SEM DATAS COMUNS ##########"); continue
    # flags por data
    info = {}
    prev_v1 = None
    for d in sorted(v1):
        drop = (prev_v1 is not None and (prev_v1 - v1[d]) > 0.5)
        info[d] = {"amort_v1": drop, "v1_drop": (prev_v1 - v1[d]) if prev_v1 is not None else 0.0}
        prev_v1 = v1[d]
    # quais linhas mostrar: ultimas 8 comuns + qualquer flag
    tail = set(common[-8:])
    show = sorted(d for d in common
                  if d in tail or info[d]["amort_v1"] or d in cfday
                  or abs(eod[d][2] - v1[d]) > 0.02)
    print(f"\n########## {tag}  ({v2n}) ##########")
    print(f"  V2 {min(eod)}..{max(eod)} ({len(eod)}d)  |  V1 {min(v1)}..{max(v1)} ({len(v1)}d)  |  comuns={len(common)}")
    print(f"  {'date':<12}{'V1_val':>13}{'V2_clean':>13}{'V2_accr':>12}{'V2_dirty':>13}{'diff':>10}  flags")
    for d in show:
        clean, acc, dirty = eod[d]; v1d = v1[d]; diff = dirty - v1d
        fl = []
        if info[d]["amort_v1"]: fl.append(f"AMORT_V1(-{info[d]['v1_drop']:.4f})")
        if d in cfday:          fl.append(f"CF_V2({cfday[d]:+.4f})")
        if abs(diff) > 0.02:    fl.append("DESCOLA")
        print(f"  {str(d):<12}{v1d:>13.6f}{clean:>13.6f}{acc:>12.6f}{dirty:>13.6f}{diff:>10.5f}  {' '.join(fl)}")
