"""
Validacao do engine contra o proprio banco. Roda no engine local (read-only).

  T1. Contagem de DU (Python) == contagem do SQL (generate_series + holidays).
  T2. Entre eventos, o PU acretua na taxa contratual (var diaria == (1+taxa)^(1/252)-1).
  T3. Amostra de fluxos: 1 serie bullet e 1 amortizante (CR-FGTS-12).

Sai com codigo != 0 se T1 ou T2 falharem.
"""
from __future__ import annotations

import sys

import psycopg2.extras

from fluxo_caixa import db, engine
from fluxo_caixa.builders import classify

REF = "CR-FGTS-12-01-SINGLE"


def t1_business_days(conn, cal) -> bool:
    s = db.load_series(conn, non_subordinated=False, name_filter=REF)[0]
    py = cal.business_days(s.pu_date, s.maturity_date)
    with conn.cursor() as cur:
        cur.execute("""
            SELECT count(*) FROM generate_series(%s::date + 1, %s::date, INTERVAL '1 day') d
            WHERE EXTRACT(isodow FROM d) < 6
              AND d::date NOT IN (SELECT date FROM holidays WHERE calendar='anbima')
        """, [s.pu_date, s.maturity_date])
        sql = cur.fetchone()[0]
    ok = py == sql
    print(f"T1 DU (Python={py} vs SQL={sql}) -> {'OK' if ok else 'FALHOU'}")
    return ok


def t2_accretion(conn, cal) -> bool:
    s = db.load_series(conn, non_subordinated=False, name_filter=REF)[0]
    hist = db.load_valuations(conn, [s.id])[s.id]
    eod = {}
    for r in hist:                       # PU de fim de dia (min p/ pegar pos-amortizacao)
        eod[r["d"]] = min(eod.get(r["d"], r["pu"]), r["pu"])
    dates = sorted(eod)
    expected = (1.0 + s.spread) ** (1.0 / 252.0) - 1.0
    worst = 0.0
    for d0, d1 in zip(dates, dates[1:]):
        du = cal.business_days(d0, d1)
        if du != 1:
            continue                     # so transicoes de 1 DU
        var = eod[d1] / eod[d0] - 1.0
        if var < -0.001:
            continue                     # pula dia de amortizacao
        worst = max(worst, abs(var - expected))
    ok = worst < 1e-6
    print(f"T2 accrual (taxa={s.spread:.4f}, esperado/dia={expected:.8f}, "
          f"maior erro={worst:.2e}) -> {'OK' if ok else 'FALHOU'}")
    return ok


def t3_samples(conn):
    df_b = engine.build_all(conn, non_subordinated=True, name_filter="CR-FGTS-15-01-SINGLE")
    df_a = engine.build_all(conn, non_subordinated=False, name_filter=REF)
    print(f"\nT3a bullet (CR-FGTS-15-01-SINGLE) classif="
          f"{df_b['classification'].iloc[0] if not df_b.empty else '??'}:")
    print(df_b[["date", "amount", "currency", "kind", "is_projected"]].to_string(index=False))
    print(f"\nT3b amortizante ({REF}) classif="
          f"{df_a['classification'].iloc[0] if not df_a.empty else '??'} "
          f"(realizado + projetado):")
    print(df_a[["date", "amount", "kind", "is_projected", "note"]].tail(12).to_string(index=False))


def main():
    conn = db.connect()
    try:
        cal = engine.BusinessCalendar(db.load_holidays(conn, "anbima"))
        ok1 = t1_business_days(conn, cal)
        ok2 = t2_accretion(conn, cal)
        t3_samples(conn)
    finally:
        conn.close()
    if not (ok1 and ok2):
        sys.exit(1)
    print("\nTodas as validacoes criticas: OK")


if __name__ == "__main__":
    main()
