"""
CLI: monta o fluxo de caixa de todas as series (pela caracteristica da serie)
e escreve um CSV. Conecta SEMPRE no engine local (read-only).

Exemplos:
  py run.py
  py run.py --name "CR-FGTS-12-01-SINGLE"
  py run.py --strategy bullet --out output/cf_bullet.csv
  py run.py --calendar b3 --asof 2026-06-01
"""
from __future__ import annotations

import argparse
import os
from datetime import datetime

from fluxo_caixa import db, engine


def _parse_date(s):
    return datetime.strptime(s, "%Y-%m-%d").date() if s else None


def main():
    ap = argparse.ArgumentParser(description="Fluxo de caixa pela caracteristica da serie")
    ap.add_argument("--asof", type=_parse_date, default=None, help="data-base (YYYY-MM-DD); default = ultimo PU")
    ap.add_argument("--calendar", default="anbima", choices=["anbima", "b3"])
    ap.add_argument("--strategy", default="extrapolate", choices=["extrapolate", "bullet"],
                    help="projecao do futuro p/ amortizantes")
    ap.add_argument("--all", action="store_true", help="inclui series subordinated")
    ap.add_argument("--name", default=None, help="filtro ILIKE pelo nome da serie")
    ap.add_argument("--threshold", type=float, default=0.005, help="queda de PU que marca amortizacao")
    ap.add_argument("--out", default=os.path.join("output", "cash_flows.csv"))
    args = ap.parse_args()

    conn = db.connect()
    try:
        df = engine.build_all(
            conn, asof=args.asof, calendar=args.calendar, strategy=args.strategy,
            non_subordinated=not args.all, name_filter=args.name,
            drop_threshold=args.threshold,
        )
    finally:
        conn.close()

    if df.empty:
        print("Nenhum fluxo gerado (filtro vazio?).")
        return

    print("== Series por classificacao ==")
    print(df.drop_duplicates("series_id")["classification"].value_counts().to_string())

    uns = df[df["classification"] == "unsupported"].drop_duplicates("series_id")
    if not uns.empty:
        print("\n== Nao suportadas ==")
        for _, r in uns.iterrows():
            print(f"  {r['series_name']:38s} {r['indexer']:12s} {r['note']}")

    print("\n== Fluxo PROJETADO por mes/moeda ==")
    print(engine.summary_by_month(df).to_string(index=False))

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    df.to_csv(args.out, index=False)
    print(f"\nCSV completo ({len(df)} linhas) -> {args.out}")


if __name__ == "__main__":
    main()
