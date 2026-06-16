-- ============================================================================
-- corrige_amort_timing_NXFGTSE34_PROD.sql            (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- TOKEN NXFGTSE34-1 (asset, lastreado direto por 265 parcelas FGTS; SEM positions).
-- V1 = correto (decisao do chefe). O V2 antecipou DUAS amortizacoes em 2 dias uteis:
--   * 2025-07-08  -> deveria cair so' em 2025-07-10  (V1)
--   * 2026-03-03  -> deveria cair so' em 2026-03-05  (V1)
-- Os OUTROS ~12 amorts ja' batem a data do V1. So' estes dois descolam (|diff|>1):
--   2025-07-08/09: V2 ~ -2.17 abaixo do V1 ;  2026-03-03/04: V2 ~ -4.78 abaixo.
--
-- COMO O V2 GUARDA O AMORT: no dia do evento ha' linhas intraday as 20:00:00.00X
--   (uma "perna" por parcela) que derrubam o clean_price em degraus; o accrued_interest
--   e' uma curva CONTINUA, independente do clean (nao muda no amort). Logo, espelhar o V1 =
--   (a) segurar o clean no nivel PRE-amort nos 2 dias extras, e
--   (b) mover o bloco de linhas-evento das 20:00 em +2 dias (com o accrued do dia de destino).
--   O accrued de cada data permanece intacto; o clean pos-amort dos dias seguintes ja' esta' certo.
--
-- Constantes (lidas do proprio V2, conferidas no LOCAL):
--   P1 Jul/2025: clean pre-amort = 67.55294091 ; accrued de 07-10 = 6.05433402
--   P2 Mar/2026: clean pre-amort = 53.23262645 ; accrued de 03-05 = 13.24912030
--   clean pos-amort (nao muda): P1 = 65.08325538 ; P2 = 48.06438746
--
-- Mira por NOME (asset='NXFGTSE34-1', methodology='amortized_cost'); nada de id hardcoded.
-- AUDITORIA: cada linha antiga -> histories (operation='update') ANTES do UPDATE.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- atalhos
CREATE TEMP TABLE _ctx ON COMMIT DROP AS
SELECT (SELECT id FROM entities WHERE name='NXFGTSE34-1')                       AS asset_id,
       (SELECT id FROM valuation_methodologies WHERE name='amortized_cost')     AS meth_id;

-- ----------------------------------------------------------------------------
-- (0) PREVIEW: EOD por dia nas duas janelas, ANTES (mostra o degrau errado)
-- ----------------------------------------------------------------------------
SELECT 'ANTES' AS quando, v.date::date AS dia,
       max(v.date) AS ult_ts,
       (SELECT clean_price FROM valuations w WHERE w.asset_id=v.asset_id
          AND w.methodology_id=v.methodology_id AND w.date=max(v.date))::float AS clean_eod,
       (SELECT (clean_price+COALESCE(accrued_interest,0)) FROM valuations w WHERE w.asset_id=v.asset_id
          AND w.methodology_id=v.methodology_id AND w.date=max(v.date))::float AS dirty_eod
FROM valuations v, _ctx c
WHERE v.asset_id=c.asset_id AND v.methodology_id=c.meth_id
  AND (v.date::date BETWEEN DATE '2025-07-07' AND DATE '2025-07-11'
    OR v.date::date BETWEEN DATE '2026-03-02' AND DATE '2026-03-06')
GROUP BY v.asset_id, v.methodology_id, v.date::date
ORDER BY dia;

-- ----------------------------------------------------------------------------
-- (1) GUARD inicial: bloco de linhas-evento esperado (7 em 07-08, 13 em 03-03)
-- ----------------------------------------------------------------------------
DO $$
DECLARE a int; m int; n1 int; n2 int;
BEGIN
  SELECT asset_id, meth_id INTO a, m FROM _ctx;
  SELECT count(*) INTO n1 FROM valuations
   WHERE asset_id=a AND methodology_id=m
     AND date >= timestamptz '2025-07-08 20:00:00-03' AND date < timestamptz '2025-07-09 00:00:00-03';
  SELECT count(*) INTO n2 FROM valuations
   WHERE asset_id=a AND methodology_id=m
     AND date >= timestamptz '2026-03-03 20:00:00-03' AND date < timestamptz '2026-03-04 00:00:00-03';
  IF n1 <> 7  THEN RAISE EXCEPTION 'P1: esperava 7 linhas-evento em 07-08 20:00, achei %', n1; END IF;
  IF n2 <> 13 THEN RAISE EXCEPTION 'P2: esperava 13 linhas-evento em 03-03 20:00, achei %', n2; END IF;
  RAISE NOTICE 'GUARD inicial OK (P1=7, P2=13 linhas-evento)';
END $$;

-- ----------------------------------------------------------------------------
-- (2) HISTORIES: loga TODA linha que sera' alterada (eventos movidos + dailies)
-- ----------------------------------------------------------------------------
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'update',
       'NXFGTSE34-1: espelha V1 — atrasa amort em 2 dias uteis (07-08->07-10 / 03-03->03-05)'
FROM valuations v, _ctx c
WHERE v.asset_id=c.asset_id AND v.methodology_id=c.meth_id
  AND ( -- linhas-evento das 20:00 (serao movidas +2d)
        (v.date >= timestamptz '2025-07-08 20:00:00-03' AND v.date < timestamptz '2025-07-09 00:00:00-03')
     OR (v.date >= timestamptz '2026-03-03 20:00:00-03' AND v.date < timestamptz '2026-03-04 00:00:00-03')
        -- dailies 00:00 que viram PRE-amort (clean sobe de pos p/ pre)
     OR v.date IN (timestamptz '2025-07-09 00:00:00-03', timestamptz '2025-07-10 00:00:00-03',
                   timestamptz '2026-03-04 00:00:00-03', timestamptz '2026-03-05 00:00:00-03') );

-- ----------------------------------------------------------------------------
-- (3a) DAILIES 00:00 -> nivel PRE-amort (accrued fica como esta')
--      P1: 07-09 e 07-10 ; P2: 03-04 e 03-05. Guarda: so' se estiverem no clean POS.
-- ----------------------------------------------------------------------------
UPDATE valuations v SET clean_price = 67.55294091
FROM _ctx c
WHERE v.asset_id=c.asset_id AND v.methodology_id=c.meth_id
  AND v.date IN (timestamptz '2025-07-09 00:00:00-03', timestamptz '2025-07-10 00:00:00-03')
  AND v.clean_price = 65.08325538;

UPDATE valuations v SET clean_price = 53.23262645
FROM _ctx c
WHERE v.asset_id=c.asset_id AND v.methodology_id=c.meth_id
  AND v.date IN (timestamptz '2026-03-04 00:00:00-03', timestamptz '2026-03-05 00:00:00-03')
  AND v.clean_price = 48.06438746;

-- ----------------------------------------------------------------------------
-- (3b) MOVE o bloco de linhas-evento +2 dias e ajusta accrued p/ o dia de destino
--      (preserva clean staircase e cash_flow de cada perna)
-- ----------------------------------------------------------------------------
UPDATE valuations v
   SET date = v.date + INTERVAL '2 days', accrued_interest = 6.05433402
FROM _ctx c
WHERE v.asset_id=c.asset_id AND v.methodology_id=c.meth_id
  AND v.date >= timestamptz '2025-07-08 20:00:00-03' AND v.date < timestamptz '2025-07-09 00:00:00-03';

UPDATE valuations v
   SET date = v.date + INTERVAL '2 days', accrued_interest = 13.24912030
FROM _ctx c
WHERE v.asset_id=c.asset_id AND v.methodology_id=c.meth_id
  AND v.date >= timestamptz '2026-03-03 20:00:00-03' AND v.date < timestamptz '2026-03-04 00:00:00-03';

-- ----------------------------------------------------------------------------
-- (4) GUARD final: estado pos-fix coerente
-- ----------------------------------------------------------------------------
DO $$
DECLARE a int; m int; bad int; tmp numeric;
BEGIN
  SELECT asset_id, meth_id INTO a, m FROM _ctx;

  -- nada mais nas 20:00 dos dias de origem; bloco aterrissou no destino
  SELECT count(*) INTO bad FROM valuations WHERE asset_id=a AND methodology_id=m
    AND ((date >= timestamptz '2025-07-08 20:00:00-03' AND date < timestamptz '2025-07-09 00:00:00-03')
      OR (date >= timestamptz '2026-03-03 20:00:00-03' AND date < timestamptz '2026-03-04 00:00:00-03'));
  IF bad <> 0 THEN RAISE EXCEPTION 'ainda ha % linha-evento na data de origem', bad; END IF;

  SELECT count(*) INTO bad FROM valuations WHERE asset_id=a AND methodology_id=m
    AND date >= timestamptz '2025-07-10 20:00:00-03' AND date < timestamptz '2025-07-11 00:00:00-03';
  IF bad <> 7 THEN RAISE EXCEPTION 'P1 destino 07-10 20:00: esperava 7, achei %', bad; END IF;
  SELECT count(*) INTO bad FROM valuations WHERE asset_id=a AND methodology_id=m
    AND date >= timestamptz '2026-03-05 20:00:00-03' AND date < timestamptz '2026-03-06 00:00:00-03';
  IF bad <> 13 THEN RAISE EXCEPTION 'P2 destino 03-05 20:00: esperava 13, achei %', bad; END IF;

  -- EOD dos dias-plateau ficou PRE-amort (clean alto)
  SELECT clean_price INTO tmp FROM valuations WHERE asset_id=a AND methodology_id=m
     AND date=(SELECT max(date) FROM valuations WHERE asset_id=a AND methodology_id=m AND date::date=DATE '2025-07-09');
  IF tmp <> 67.55294091 THEN RAISE EXCEPTION 'P1 07-09 EOD clean=% (esperava 67.55294091)', tmp; END IF;
  SELECT clean_price INTO tmp FROM valuations WHERE asset_id=a AND methodology_id=m
     AND date=(SELECT max(date) FROM valuations WHERE asset_id=a AND methodology_id=m AND date::date=DATE '2026-03-04');
  IF tmp <> 53.23262645 THEN RAISE EXCEPTION 'P2 03-04 EOD clean=% (esperava 53.23262645)', tmp; END IF;

  -- EOD do dia do amort ficou POS-amort (clean baixo) no destino
  SELECT clean_price INTO tmp FROM valuations WHERE asset_id=a AND methodology_id=m
     AND date=(SELECT max(date) FROM valuations WHERE asset_id=a AND methodology_id=m AND date::date=DATE '2025-07-10');
  IF tmp <> 65.08325538 THEN RAISE EXCEPTION 'P1 07-10 EOD clean=% (esperava 65.08325538)', tmp; END IF;
  SELECT clean_price INTO tmp FROM valuations WHERE asset_id=a AND methodology_id=m
     AND date=(SELECT max(date) FROM valuations WHERE asset_id=a AND methodology_id=m AND date::date=DATE '2026-03-05');
  IF tmp <> 48.06438746 THEN RAISE EXCEPTION 'P2 03-05 EOD clean=% (esperava 48.06438746)', tmp; END IF;

  RAISE NOTICE 'GUARD final OK: amort movido p/ 07-10 e 03-05; plateaus pre-amort em 07-08/09 e 03-03/04';
END $$;

-- ----------------------------------------------------------------------------
-- (5) POST-CHECK: EOD por dia, DEPOIS (degrau deve ter sumido)
-- ----------------------------------------------------------------------------
SELECT 'DEPOIS' AS quando, v.date::date AS dia, max(v.date) AS ult_ts,
       (SELECT clean_price FROM valuations w WHERE w.asset_id=v.asset_id
          AND w.methodology_id=v.methodology_id AND w.date=max(v.date))::float AS clean_eod,
       (SELECT (clean_price+COALESCE(accrued_interest,0)) FROM valuations w WHERE w.asset_id=v.asset_id
          AND w.methodology_id=v.methodology_id AND w.date=max(v.date))::float AS dirty_eod
FROM valuations v, _ctx c
WHERE v.asset_id=c.asset_id AND v.methodology_id=c.meth_id
  AND (v.date::date BETWEEN DATE '2025-07-07' AND DATE '2025-07-11'
    OR v.date::date BETWEEN DATE '2026-03-02' AND DATE '2026-03-06')
GROUP BY v.asset_id, v.methodology_id, v.date::date
ORDER BY dia;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
