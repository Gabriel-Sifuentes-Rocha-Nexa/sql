-- ============================================================================
-- corrige_cf_tokens_78SIM_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- A correcao dos 78 SIM foi aplicada so nas SERIES; os TOKENS que as espelham
-- ficaram com cash_flow = -clean_price (bug) nesses eventos. Aqui sincronizo cada
-- token com a sua serie: cash_flow do token := cash_flow da serie, NAS LINHAS-EVENTO
-- ONDE DIFEREM. clean_price/accrued ja sao iguais (so o cash_flow diverge).
--
-- Pareamento serie<->token (17): token_id = serie_id + 1, CONFIRMADO POR QUANTIDADE
--   (securitization_series.quantity == tokens.issuance_amount), inclusive as 3 tranches
--   do FGTS-08 (348000 / 32000 / 20000).
-- Alinhamento evento<->evento: mesmo dia + mesmo clean_price + mesmo accrued (impressao
--   digital da tranche) -> robusto mesmo com multiplas tranches sob a mesma mae.
-- So toca onde cash_flow DIFERE -> nao mexe em DIVERGE/nao-corrigidos (serie e token
--   batem no estado bugado) nem em dailies.
--
-- AUDITORIA: cada linha antiga do token vai p/ `histories` (operation='update') ANTES do UPDATE.
-- DRY-RUN: BEGIN..ROLLBACK; trocar por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

CREATE TEMP TABLE _pairs(serie_id bigint, token_id bigint) ON COMMIT DROP;
INSERT INTO _pairs(serie_id, token_id)
SELECT x, x+1 FROM (VALUES
  (20450),(159525),(1035059),(1047751),(1052806),(1057259),(1057309),(1057270),
  (1057319),(1057322),(1057325),(1057328),(1058788),(1058786),(1058784),(1057455),(1058821)
) v(x);

-- linhas-evento do token a corrigir (cash_flow difere da serie pareada)
CREATE TEMP TABLE _fix ON COMMIT DROP AS
SELECT vt.id AS token_val_id, p.serie_id, p.token_id, vt.date::date AS dia,
       vt.clean_price, vt.cash_flow AS cf_old, vs.cash_flow AS cf_new
FROM _pairs p
JOIN valuations vt ON vt.asset_id = p.token_id  AND vt.cash_flow <> 0
JOIN valuations vs ON vs.asset_id = p.serie_id
                  AND vs.date::date = vt.date::date
                  AND vs.clean_price = vt.clean_price
                  AND vs.accrued_interest IS NOT DISTINCT FROM vt.accrued_interest
                  AND vs.cash_flow <> 0
WHERE vt.cash_flow IS DISTINCT FROM vs.cash_flow;

-- (1) PREVIEW: quantos eventos por token
SELECT te.name AS token, count(*) AS difs
FROM _fix f JOIN entities te ON te.id = f.token_id
GROUP BY te.name ORDER BY te.name;
SELECT count(*) AS total_a_corrigir FROM _fix;

-- (2) GUARDA: sem ambiguidade (cada linha do token casa exatamente 1 evento da serie)
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM (SELECT token_val_id FROM _fix GROUP BY token_val_id HAVING count(*) <> 1) x;
  IF n > 0 THEN RAISE EXCEPTION '% linha(s) de token casaram <>1 evento de serie (ambiguidade)', n; END IF;
END $$;

-- (3) histories (linha antiga do token) antes do UPDATE
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'update',
       'corrige cash_flow do token p/ casar com a serie (78 SIM; token estava = -clean_price)'
FROM valuations v JOIN _fix f ON f.token_val_id = v.id;

-- (4) UPDATE
UPDATE valuations v SET cash_flow = f.cf_new FROM _fix f WHERE v.id = f.token_val_id;

-- (5) GUARDA FINAL: nenhum par serie<->token difere mais em cash_flow de evento
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n
  FROM _pairs p
  JOIN valuations vt ON vt.asset_id = p.token_id AND vt.cash_flow <> 0
  JOIN valuations vs ON vs.asset_id = p.serie_id AND vs.date::date = vt.date::date
                    AND vs.clean_price = vt.clean_price
                    AND vs.accrued_interest IS NOT DISTINCT FROM vt.accrued_interest
                    AND vs.cash_flow <> 0
  WHERE vt.cash_flow IS DISTINCT FROM vs.cash_flow;
  IF n <> 0 THEN RAISE EXCEPTION 'ainda ha % evento(s) token<>serie apos o update', n; END IF;
  RAISE NOTICE 'OK: todos os pares serie<->token com cash_flow de evento identico';
END $$;

-- (6) POST-CHECK: total gravado em histories nesta transacao
SELECT count(*) AS gravadas_em_histories
FROM histories
WHERE created_by='gabriel_sifuentes' AND operation='update'
  AND description LIKE 'corrige cash_flow do token p/ casar%';

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
