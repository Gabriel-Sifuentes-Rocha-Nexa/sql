"""
gen_corrige_cash_flow_SIM.py
---------------------------------------------------------------------------------------
GERADOR (nao toca banco): le tabela_juros_v1_v2.csv, filtra os casos bate=='SIM' e
emite um .sql AUTOCONTIDO (corrige_cash_flow_SIM_PROD.sql) que corrige o cash_flow
desses eventos no banco-alvo, salvando a linha antiga em `histories`.

Por que isso e seguro:
  - O .sql roda numa transacao que TERMINA EM ROLLBACK (dry-run). Pra aplicar de verdade,
    voce troca o ROLLBACK final por COMMIT.
  - Antes de qualquer escrita, um bloco DO valida (e ABORTA a transacao via RAISE) se:
      (a) os 78 pares serie/data nao resolverem exatamente 1 linha-evento cada, ou
      (b) algum cash_flow atual nao for == -clean_price (a assinatura do bug).
    Como apos aplicar o cash_flow deixa de ser -clean_price, re-rodar aborta sozinho
    (protege contra aplicar duas vezes).
  - histories (old_value = to_jsonb da linha) e' inserido ANTES do UPDATE; created_by
    = 'gabriel_sifuentes'.

cash_flow novo = juros_V1 (metadata V1, fonte-de-verdade; nos casos SIM == juros_V2).

USO:
  py gen_corrige_cash_flow_SIM.py      # gera corrige_cash_flow_SIM_PROD.sql
  # depois rode o .sql no cliente apontando para o banco-alvo (PROD tunel :5003 ou LOCAL).
"""
import csv
import os

HERE = os.path.dirname(os.path.abspath(__file__))
CSV_IN = os.path.join(HERE, "tabela_juros_v1_v2.csv")
SQL_OUT = os.path.join(HERE, "corrige_cash_flow_SIM_PROD.sql")

DESC = ("corrige cash_flow do evento de amortizacao "
        "(estava = -clean_price; valor correto = juros pago, V1=V2)")


def load_sim():
    rows = []
    with open(CSV_IN, newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if r["bate"].strip() != "SIM":
                continue
            cf_new = r["juros_V1"].strip()
            assert cf_new not in ("", "NaN"), f"juros_V1 vazio em {r['serie']} {r['date']}"
            rows.append((r["serie"].strip(), r["date"].strip(), cf_new))
    rows.sort(key=lambda t: (t[0], t[1]))
    return rows


def build_sql(rows):
    values = ",\n".join(
        f"    ('{serie}'::text, '{d}'::date, {cf_new}::numeric)"
        for serie, d, cf_new in rows
    )
    n = len(rows)
    return f"""\
-- ============================================================================
-- corrige_cash_flow_SIM_PROD.sql   (GERADO por gen_corrige_cash_flow_SIM.py)
-- ----------------------------------------------------------------------------
-- Corrige `valuations.cash_flow` dos {n} eventos de amortizacao classificados SIM
-- (queda intraday do preco total no V2 == juros pago no V1). O valor estava lancado
-- ERRADO como -clean_price; o correto = juros pago (juros_V1, = juros_V2 nos SIM).
-- A linha antiga e' salva em `histories` (old_value = to_jsonb) ANTES do UPDATE.
--
-- SEGURANCA:
--   * Roda dentro de BEGIN ... ROLLBACK (DRY-RUN: nada muda). Para APLICAR, troque o
--     ROLLBACK final por COMMIT.
--   * Bloco DO aborta a transacao inteira (RAISE) se algum par serie/data nao resolver
--     exatamente 1 linha-evento OU se algum cash_flow atual nao for == -clean_price.
--     -> re-rodar apos aplicar aborta sozinho (cash_flow ja nao e -clean_price).
--   * So altera a coluna cash_flow. clean_price/accrued NAO sao tocados.
--   * NAO inclui os 4 GLITCH (11-14) nem os DIVERGE (08/23/25) — esses sao tratados a parte.
--
-- COMO RODAR (aponte para o banco-alvo: PROD tunel :5003 ou LOCAL :5432):
--   psql "postgresql://USER:***@HOST:PORT/engine" -f corrige_cash_flow_SIM_PROD.sql
--   # confira o preview e o post-check; depois troque ROLLBACK->COMMIT e rode de novo.
-- ============================================================================

BEGIN;

-- (1) entrada: {n} eventos SIM (serie, data, cash_flow correto = juros_V1)
CREATE TEMP TABLE _corr(serie text, d date, cf_new numeric) ON COMMIT DROP;
INSERT INTO _corr (serie, d, cf_new) VALUES
{values};

-- (2) resolve a linha-evento de cada par (amortized_cost, mesma data, cash_flow<>0)
CREATE TEMP TABLE _resolved ON COMMIT DROP AS
SELECT v.id AS val_id, c.serie, c.d, v.cash_flow AS cf_old, v.clean_price, c.cf_new
FROM _corr c
JOIN entities e   ON e.name = c.serie
JOIN valuations v ON v.asset_id = e.id
                 AND v.methodology_id = (SELECT id FROM valuation_methodologies WHERE name = 'amortized_cost')
                 AND v.date::date = c.d
                 AND v.cash_flow IS NOT NULL AND v.cash_flow <> 0;

-- (3) PREVIEW (sempre imprime; nao altera nada)
SELECT serie, d, val_id, cf_old, clean_price, cf_new,
       round((cf_old + clean_price)::numeric, 6) AS bug_check_deve_ser_0
FROM _resolved
ORDER BY serie, d;

-- (4) GUARDA: aborta a transacao se algo nao bate
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _corr;
  IF n <> {n} THEN RAISE EXCEPTION '_corr tem % linhas (esperado {n})', n; END IF;

  SELECT count(*) INTO n FROM (
    SELECT c.serie, c.d
    FROM _corr c
    LEFT JOIN _resolved r ON r.serie = c.serie AND r.d = c.d
    GROUP BY c.serie, c.d
    HAVING count(r.val_id) <> 1
  ) x;
  IF n > 0 THEN RAISE EXCEPTION '% par(es) serie/data nao resolveram exatamente 1 linha-evento', n; END IF;

  SELECT count(*) INTO n FROM _resolved WHERE abs(cf_old + clean_price) > 0.01;
  IF n > 0 THEN RAISE EXCEPTION 'assinatura do bug falhou em % linha(s) (cash_flow <> -clean_price)', n; END IF;
END $$;

-- (5) histories: salva a linha ANTIGA inteira (jsonb) antes de alterar
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'update', '{DESC}'
FROM valuations v
JOIN _resolved r ON r.val_id = v.id;

-- (6) UPDATE do cash_flow
UPDATE valuations v
SET cash_flow = r.cf_new
FROM _resolved r
WHERE v.id = r.val_id;

-- (7) POST-CHECK
SELECT r.serie, r.d, r.cf_old, v.cash_flow AS cf_now, r.cf_new,
       CASE WHEN abs(v.cash_flow - r.cf_new) < 1e-6 THEN 'ok' ELSE 'ERRO' END AS check
FROM _resolved r
JOIN valuations v ON v.id = r.val_id
ORDER BY r.serie, r.d;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar de verdade.
"""


def main():
    rows = load_sim()
    sql = build_sql(rows)
    with open(SQL_OUT, "w", encoding="utf-8") as fh:
        fh.write(sql)
    print(f"SIM events: {len(rows)}")
    print(f"sum(cf_new) = {sum(float(r[2]) for r in rows):.6f}")
    print(f"OK -> {SQL_OUT}")


if __name__ == "__main__":
    main()
