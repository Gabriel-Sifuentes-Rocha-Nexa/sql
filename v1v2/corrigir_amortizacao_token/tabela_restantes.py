"""
tabela_restantes.py
---------------------------------------------------------------------------------------
Tabela de DECISAO dos casos que sobraram (tudo que NAO e' SIM apos a correcao dos 78).
Le os dois CSVs ja gerados (nao toca banco):
  - tabela_juros_v1_v2.csv      (precos D-1/D0 V1xV2, juros_V1, juros_V2, bate)
  - comparacao_cash_flow_v1_v2.csv (clean_before/after, clean_drop, cash_flow_atual)

Para cada caso restante, classifica e sugere acao:
  GLITCH        -> clean caiu certo (= V1), so o dirty intraday contaminou. Corrigir SO o
                  cash_flow := juros_V1 e' SEGURO.
  DIVERGE       -> clean_price do V2 tambem esta errado (V2 sub/lumped-amortizou). Corrigir
                  cash_flow sozinho recria a inconsistencia -> precisa corrigir clean_price tb.
  NAO_LANCADO   -> V2 nao tem o evento (so a diaria, ou nem valuation). Nao da UPDATE; precisa
                  LANCAR o evento (ETL/engine).

Saida: console + CSV (tabela_restantes.csv).
"""
import csv
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
JUROS = os.path.join(HERE, "tabela_juros_v1_v2.csv")
COMP = os.path.join(HERE, "comparacao_cash_flow_v1_v2.csv")
OUT = os.path.join(HERE, "tabela_restantes.csv")
TOL = 0.01


def fnum(s):
    if s is None:
        return None
    s = s.strip()
    if s == "" or s.lower() == "nan":
        return None
    try:
        v = float(s)
        return None if math.isnan(v) else v
    except ValueError:
        return None


def load_csv(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def main():
    juros = load_csv(JUROS)
    comp_by_key = {(r["serie"], r["date"]): r for r in load_csv(COMP)}

    # ordem de exibicao por categoria (acionavel primeiro)
    ordem = {"GLITCH": 0, "DIVERGE": 1, "NAO_LANCADO (falta evento)": 2,
             "NAO_LANCADO (sem valuation)": 3}
    rows = []

    for p in juros:
        if p["bate"].strip() == "SIM":
            continue
        serie, data = p["serie"].strip(), p["date"].strip()
        comp = comp_by_key.get((serie, data), {})

        jv1 = fnum(p.get("juros_V1"))
        jv2 = fnum(p.get("juros_V2"))
        pD0_v2 = fnum(p.get("p_D0_V2"))
        clean_drop = fnum(comp.get("clean_drop"))
        cf_atual = fnum(comp.get("cash_flow_atual"))

        # ---- classificacao ----
        if pD0_v2 is None:
            cat = "NAO_LANCADO (sem valuation)"
            seguro = "NAO - precisa LANCAR o evento (V2 nem tem valuation em D0)"
        elif cf_atual is None:
            cat = "NAO_LANCADO (falta evento)"
            seguro = "NAO - precisa LANCAR o evento (so ha a diaria, sem cash_flow)"
        elif clean_drop is not None and abs(clean_drop - (jv1 or 0)) < TOL:
            cat = "GLITCH"
            seguro = "SIM - corrigir so cash_flow := juros_V1 (clean ja esta certo)"
        else:
            cat = "DIVERGE"
            seguro = "NAO - clean_price tb errado; corrigir cash_flow sozinho recria a inconsistencia"

        rows.append({
            "categoria": cat,
            "serie": serie,
            "data": data,
            "p_Dm1_V1": fnum(p.get("p_Dm1_V1")),
            "p_Dm1_V2": fnum(p.get("p_Dm1_V2")),
            "p_D0_V1": fnum(p.get("p_D0_V1")),
            "p_D0_V2": pD0_v2,
            "juros_V1": jv1,
            "clean_drop_V2": clean_drop,
            "juros_V2_dirty": jv2,
            "cash_flow_atual": cf_atual,
            "cf_correto": jv1,
            "seguro_corrigir": seguro,
        })

    rows.sort(key=lambda r: (ordem.get(r["categoria"], 9), r["serie"], r["data"]))

    cols = ["categoria", "serie", "data", "p_Dm1_V1", "p_Dm1_V2", "p_D0_V1", "p_D0_V2",
            "juros_V1", "clean_drop_V2", "juros_V2_dirty", "cash_flow_atual",
            "cf_correto", "seguro_corrigir"]
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)

    # ---- render compacto no console ----
    def fmt(x):
        return "" if x is None else f"{x:>11.6f}"

    print(f"{'categoria':<28} {'serie':<27} {'data':<11} {'juros_V1':>11} {'clean_dropV2':>13} "
          f"{'cf_atual':>13} {'cf_correto':>11}")
    print("-" * 122)
    last = None
    for r in rows:
        if r["categoria"] != last:
            print()
            last = r["categoria"]
        print(f"{r['categoria']:<28} {r['serie']:<27} {r['data']:<11} {fmt(r['juros_V1'])} "
              f"{fmt(r['clean_drop_V2']):>13} {fmt(r['cash_flow_atual']):>13} {fmt(r['cf_correto'])}")

    print("\n=== contagem por categoria ===")
    cnt = {}
    for r in rows:
        cnt[r["categoria"]] = cnt.get(r["categoria"], 0) + 1
    for k in sorted(cnt, key=lambda c: ordem.get(c, 9)):
        print(f"  {k:<30} {cnt[k]}")
    print(f"\nTotal restantes: {len(rows)}")
    print(f"CSV: {OUT}")


if __name__ == "__main__":
    main()
