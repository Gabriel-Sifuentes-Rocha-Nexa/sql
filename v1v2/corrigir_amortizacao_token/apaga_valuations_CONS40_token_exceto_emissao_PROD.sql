-- ============================================================================
-- apaga_valuations_CONS40_token_exceto_emissao_PROD.sql     (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- CR-40 token NXCOD29-4 (asset_id 1395536): apagar TODAS as valuations menos a 1a
-- (a emissao). A emissao (id 26425189, 06-02 12:01:01) e' a unica CERTA: spread_over_indexer
-- = 0.17. As dailies 06-03+ foram escritas com spread=0 (engine nao ativou o accrual pq o
-- token nao foi integralizado) -> accrued=0. Limpa tudo menos a emissao p/ o engine
-- re-accruar do anchor certo (spread 0.17) APOS a integralizacao.
-- AUDITORIA: linha antiga -> histories (delete) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: o que mantem (emissao) e o que apaga
SELECT v.id, v.date, v.clean_price, v.accrued_interest, v.spread_over_indexer,
       CASE WHEN v.id = 26425189 THEN '(mantem emissao)' ELSE '-> DELETE' END AS acao
FROM valuations v WHERE v.asset_id=1395536 ORDER BY v.date;

-- (1) histories — todas menos a emissao
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'CR-40 token (1395536): apaga dailies spread=0/accrued=0 (mantem so emissao 06-02 spread 0.17) p/ re-accruar apos integralizacao'
FROM valuations v
WHERE v.asset_id=1395536 AND v.id <> 26425189;

-- (2) DELETE todas menos a emissao
DELETE FROM valuations
WHERE asset_id=1395536 AND id <> 26425189;

-- (3) GUARDA: resta 1 linha (a emissao), spread 0.17, clean 100
DO $$
DECLARE n int; sp numeric; cl numeric;
BEGIN
  SELECT count(*) INTO n FROM valuations WHERE asset_id=1395536;
  IF n <> 1 THEN RAISE EXCEPTION 'restaram % linhas (esperado 1)', n; END IF;
  SELECT spread_over_indexer, clean_price INTO sp, cl FROM valuations WHERE asset_id=1395536;
  IF sp <> 0.17 OR cl <> 100 THEN RAISE EXCEPTION 'linha restante inesperada (spread=%, clean=%)', sp, cl; END IF;
  RAISE NOTICE 'OK: restou so a emissao (spread 0.17, clean 100)';
END $$;

-- (4) POST-CHECK
SELECT v.id, v.date, v.clean_price, v.accrued_interest, v.spread_over_indexer, v.last_valuation_flag AS vig
FROM valuations v WHERE v.asset_id=1395536 ORDER BY v.date;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
