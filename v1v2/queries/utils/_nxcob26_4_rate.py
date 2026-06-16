"""NXCOB26-4 (token, strategy CO) no V1 — serie de valuations e taxa implicita ao longo do tempo.
READ-ONLY. Computa o yield anualizado dia-a-dia (base 252 du aprox via calendario) e marca:
  JUMP    = variacao diaria > 3x a mediana (possivel evento/glitch)
  QUEDA   = value caiu vs dia anterior (amortizacao/marcacao negativa)
  GAP>7d  = buraco na serie
Uso: ver _nxcob26_4_meta.sql para o token. DATABASE_URL deve apontar p/ V1 (Supabase).
"""
import os, statistics, datetime
import psycopg2

DSN = os.environ["DATABASE_URL"]
NAME = "NXCOB26-4"

SQL = """
WITH s AS (SELECT aux_id FROM securities WHERE full_name=%s)
SELECT v.valuation_date::date d, v.value::float val
FROM s JOIN valuations v ON v.aux_id = s.aux_id
WHERE v.type IN ('token','token_adjusted_price') OR TRUE
ORDER BY v.valuation_date;
"""

c = psycopg2.connect(DSN); c.set_session(readonly=True, autocommit=True)
with c.cursor() as cur:
    cur.execute(SQL, (NAME,))
    rows = cur.fetchall()
c.close()

if not rows:
    print("SEM valuations p/", NAME); raise SystemExit

print(f"{NAME}: {len(rows)} valuations  {rows[0][0]} .. {rows[-1][0]}")
print(f"  value inicial={rows[0][1]:.4f}  final={rows[-1][1]:.4f}")

# taxa implicita dia-a-dia
daily = []
for (d0, v0), (d1, v1) in zip(rows, rows[1:]):
    dd = (d1 - d0).days
    if dd <= 0 or v0 <= 0 or v1 <= 0:
        continue
    r_ann = (v1 / v0) ** (365.0 / dd) - 1.0
    daily.append((d1, dd, v0, v1, v1 / v0 - 1.0, r_ann))

if daily:
    rs = [x[5] for x in daily]
    med = statistics.median(rs)
    print(f"  taxa anual implicita: mediana={med*100:.2f}%  min={min(rs)*100:.2f}%  max={max(rs)*100:.2f}%")
    abs_dev = [abs(x[4]) for x in daily]
    med_dev = statistics.median(abs_dev) or 1e-9
    print(f"\n  {'date':<12}{'gap':>4}{'value':>16}{'ret_dia%':>11}{'taxa_ano%':>12}  flags")
    for d1, dd, v0, v1, rday, rann in daily:
        fl = []
        if abs(rday) > 5 * med_dev: fl.append("JUMP")
        if v1 < v0:                 fl.append("QUEDA")
        if dd > 7:                  fl.append(f"GAP{dd}d")
        if abs(rann) > 0.5:         fl.append("TAXA_ABSURDA")
        if fl:
            print(f"  {str(d1):<12}{dd:>4}{v1:>16.4f}{rday*100:>11.4f}{rann*100:>12.2f}  {' '.join(fl)}")
    print("  (so' linhas com flag; sem flag = taxa estavel)")
