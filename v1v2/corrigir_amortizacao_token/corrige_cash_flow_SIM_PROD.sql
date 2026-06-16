-- ============================================================================
-- corrige_cash_flow_SIM_PROD.sql   (GERADO por gen_corrige_cash_flow_SIM.py)
-- ----------------------------------------------------------------------------
-- Corrige `valuations.cash_flow` dos 78 eventos de amortizacao classificados SIM
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

-- (1) entrada: 78 eventos SIM (serie, data, cash_flow correto = juros_V1)
CREATE TEMP TABLE _corr(serie text, d date, cf_new numeric) ON COMMIT DROP;
INSERT INTO _corr (serie, d, cf_new) VALUES
    ('CR-CONSORTIUMS-13-01-SINGLE'::text, '2026-05-15'::date, 24.2026365::numeric),
    ('CR-CONSORTIUMS-29-01-SINGLE'::text, '2026-05-05'::date, 63.26::numeric),
    ('CR-CONSORTIUMS-29-01-SINGLE'::text, '2026-05-15'::date, 14.7620208::numeric),
    ('CR-FGTS-01-01-SINGLE'::text, '2025-07-08'::date, 1.8612198::numeric),
    ('CR-FGTS-01-01-SINGLE'::text, '2025-08-05'::date, 2.70453069::numeric),
    ('CR-FGTS-01-01-SINGLE'::text, '2025-09-08'::date, 2.51434257::numeric),
    ('CR-FGTS-01-01-SINGLE'::text, '2025-10-06'::date, 3.30800099::numeric),
    ('CR-FGTS-01-01-SINGLE'::text, '2025-11-06'::date, 2.144123::numeric),
    ('CR-FGTS-01-01-SINGLE'::text, '2025-12-08'::date, 3.708470297::numeric),
    ('CR-FGTS-01-01-SINGLE'::text, '2026-01-09'::date, 4.313555446::numeric),
    ('CR-FGTS-01-01-SINGLE'::text, '2026-02-11'::date, 5.854921782::numeric),
    ('CR-FGTS-01-01-SINGLE'::text, '2026-03-05'::date, 4.95281485148515::numeric),
    ('CR-FGTS-01-01-SINGLE'::text, '2026-04-07'::date, 0.01736733::numeric),
    ('CR-FGTS-01-01-SINGLE'::text, '2026-05-07'::date, 5.15741881::numeric),
    ('CR-FGTS-02-01-SINGLE'::text, '2025-10-06'::date, 3.046065::numeric),
    ('CR-FGTS-02-01-SINGLE'::text, '2025-11-06'::date, 1.776337::numeric),
    ('CR-FGTS-02-01-SINGLE'::text, '2025-12-08'::date, 3.499611483::numeric),
    ('CR-FGTS-02-01-SINGLE'::text, '2026-01-09'::date, 4.203564593::numeric),
    ('CR-FGTS-02-01-SINGLE'::text, '2026-02-11'::date, 3.36421244::numeric),
    ('CR-FGTS-02-01-SINGLE'::text, '2026-03-05'::date, 4.26048516746411::numeric),
    ('CR-FGTS-02-01-SINGLE'::text, '2026-04-07'::date, 3.71718373::numeric),
    ('CR-FGTS-02-01-SINGLE'::text, '2026-05-07'::date, 3.62029282::numeric),
    ('CR-FGTS-03-01-SINGLE'::text, '2025-10-06'::date, 3.004407::numeric),
    ('CR-FGTS-03-01-SINGLE'::text, '2025-11-06'::date, 1.485096::numeric),
    ('CR-FGTS-03-01-SINGLE'::text, '2025-12-08'::date, 4.300844::numeric),
    ('CR-FGTS-03-01-SINGLE'::text, '2026-01-09'::date, 3.366075::numeric),
    ('CR-FGTS-03-01-SINGLE'::text, '2026-02-10'::date, 3.623569::numeric),
    ('CR-FGTS-03-01-SINGLE'::text, '2026-03-05'::date, 3.418588::numeric),
    ('CR-FGTS-03-01-SINGLE'::text, '2026-04-07'::date, 3.186226::numeric),
    ('CR-FGTS-03-01-SINGLE'::text, '2026-05-06'::date, 4.230157::numeric),
    ('CR-FGTS-04-01-SINGLE'::text, '2025-10-06'::date, 2.200293::numeric),
    ('CR-FGTS-04-01-SINGLE'::text, '2025-11-06'::date, 1.267642::numeric),
    ('CR-FGTS-04-01-SINGLE'::text, '2025-11-14'::date, 1.052282::numeric),
    ('CR-FGTS-04-01-SINGLE'::text, '2025-12-08'::date, 3.41717::numeric),
    ('CR-FGTS-04-01-SINGLE'::text, '2026-01-09'::date, 2.743830667::numeric),
    ('CR-FGTS-04-01-SINGLE'::text, '2026-02-10'::date, 3.397637::numeric),
    ('CR-FGTS-04-01-SINGLE'::text, '2026-03-05'::date, 3.74567466666667::numeric),
    ('CR-FGTS-04-01-SINGLE'::text, '2026-04-07'::date, 3.998084::numeric),
    ('CR-FGTS-04-01-SINGLE'::text, '2026-05-06'::date, 4.13684333::numeric),
    ('CR-FGTS-05-01-SINGLE'::text, '2025-10-06'::date, 1.789635::numeric),
    ('CR-FGTS-05-01-SINGLE'::text, '2025-11-06'::date, 1.728228::numeric),
    ('CR-FGTS-05-01-SINGLE'::text, '2025-11-14'::date, 1.0448064::numeric),
    ('CR-FGTS-05-01-SINGLE'::text, '2025-12-08'::date, 2.8754748::numeric),
    ('CR-FGTS-05-01-SINGLE'::text, '2026-01-09'::date, 3.098246::numeric),
    ('CR-FGTS-05-01-SINGLE'::text, '2026-02-10'::date, 3.38244::numeric),
    ('CR-FGTS-05-01-SINGLE'::text, '2026-03-05'::date, 3.16067::numeric),
    ('CR-FGTS-05-01-SINGLE'::text, '2026-04-07'::date, 3.2352796::numeric),
    ('CR-FGTS-05-01-SINGLE'::text, '2026-05-06'::date, 3.364726::numeric),
    ('CR-FGTS-06-01-SINGLE'::text, '2025-11-06'::date, 1.743525::numeric),
    ('CR-FGTS-06-01-SINGLE'::text, '2025-12-08'::date, 4.8261752::numeric),
    ('CR-FGTS-06-01-SINGLE'::text, '2026-01-09'::date, 2.968068::numeric),
    ('CR-FGTS-06-01-SINGLE'::text, '2026-02-10'::date, 3.177059::numeric),
    ('CR-FGTS-06-01-SINGLE'::text, '2026-03-05'::date, 3.4368788::numeric),
    ('CR-FGTS-06-01-SINGLE'::text, '2026-04-07'::date, 3.3742176::numeric),
    ('CR-FGTS-06-01-SINGLE'::text, '2026-05-06'::date, 3.9000132::numeric),
    ('CR-FGTS-07-01-SINGLE'::text, '2025-11-18'::date, 3.013492263::numeric),
    ('CR-FGTS-07-01-SINGLE'::text, '2025-12-09'::date, 4.744332409::numeric),
    ('CR-FGTS-07-01-SINGLE'::text, '2026-01-13'::date, 3.29505357::numeric),
    ('CR-FGTS-07-01-SINGLE'::text, '2026-02-12'::date, 3.08188029::numeric),
    ('CR-FGTS-07-01-SINGLE'::text, '2026-03-06'::date, 3.47862336::numeric),
    ('CR-FGTS-07-01-SINGLE'::text, '2026-04-08'::date, 3.22107547::numeric),
    ('CR-FGTS-07-01-SINGLE'::text, '2026-05-07'::date, 3.692687299::numeric),
    ('CR-FGTS-08-03-SUBORDINATED'::text, '2026-04-23'::date, 90.0::numeric),
    ('CR-FGTS-10-01-SINGLE'::text, '2025-12-08'::date, 3.247898773::numeric),
    ('CR-FGTS-10-01-SINGLE'::text, '2026-01-09'::date, 3.569248466::numeric),
    ('CR-FGTS-10-01-SINGLE'::text, '2026-02-10'::date, 2.980736::numeric),
    ('CR-FGTS-10-01-SINGLE'::text, '2026-03-05'::date, 3.51972515337423::numeric),
    ('CR-FGTS-10-01-SINGLE'::text, '2026-04-07'::date, 3.93214356::numeric),
    ('CR-FGTS-10-01-SINGLE'::text, '2026-05-06'::date, 4.3744092::numeric),
    ('CR-FGTS-12-01-SINGLE'::text, '2025-12-08'::date, 3.491146667::numeric),
    ('CR-FGTS-12-01-SINGLE'::text, '2026-01-09'::date, 3.394521111::numeric),
    ('CR-FGTS-12-01-SINGLE'::text, '2026-02-11'::date, 3.743943333::numeric),
    ('CR-FGTS-12-01-SINGLE'::text, '2026-03-05'::date, 3.26038222222222::numeric),
    ('CR-FGTS-12-01-SINGLE'::text, '2026-04-07'::date, 3.63093889::numeric),
    ('CR-FGTS-12-01-SINGLE'::text, '2026-05-07'::date, 3.47554889::numeric),
    ('CR-FGTS-15-01-SINGLE'::text, '2026-03-05'::date, 4.21384888888889::numeric),
    ('CR-FGTS-15-01-SINGLE'::text, '2026-04-07'::date, 3.47692889::numeric),
    ('CR-FGTS-15-01-SINGLE'::text, '2026-05-07'::date, 3.8170237::numeric);

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
  IF n <> 78 THEN RAISE EXCEPTION '_corr tem % linhas (esperado 78)', n; END IF;

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
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'update', 'corrige cash_flow do evento de amortizacao (estava = -clean_price; valor correto = juros pago, V1=V2)'
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
