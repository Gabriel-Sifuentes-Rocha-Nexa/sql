-- ============================================================
-- Rename dos 6 tokens FGTS no V2 LOCAL p/ ESPELHAR o V1 (versao SQL)
-- Banco ALVO: V2 LOCAL (engine @ 127.0.0.1:5432). NUNCA prod / NUNCA V1.
-- ------------------------------------------------------------
-- Rode no SEU client (psql/DBeaver). O run_query.py e read-only e barra UPDATE.
-- Equivalente ao fgts_token_rename_v2.py (esse tem pre/post-check automatico).
--
-- Os nomes formam uma PERMUTACAO FECHADA (o nome final de um esta ocupado por
-- outro), entao renomeia em 2 FASES (nomes temporarios) p/ nunca violar o UNIQUE
-- de entities.name / financial_accounts.name no meio. Tudo em 1 transacao.
--
-- Mapa (entity_id, fa_id, atual -> final):
--   20451   9632  NXFGTSL34-1 -> NXFGTSJ34-1   (CR-01)
--   159526  9915  NXFGTSI35-1 -> NXFGTSH35-1   (CR-02)
--   1035060 9917  NXFGTSI35-3 -> NXFGTSH35-2   (CR-03)
--   1047752 9940  NXFGTSI35-4 -> NXFGTSI35-1   (CR-04)
--   1052807 9972  NXFGTSI35-5 -> NXFGTSI35-2   (CR-05)
--   1057260 10005 NXFGTSI35-6 -> NXFGTSI35-3   (CR-06)
--   orfa: entity 262653 'NXFGTSI35-2' (fa 9916) -> ARQUIVAR (libera o nome -2)
-- ============================================================


-- ------------------------------------------------------------
-- PASSO 0 — PRE-CHECK (read-only): confirme que o estado casa com o mapa.
-- Esperado: nome_ok = true nas 6 linhas.
-- ------------------------------------------------------------
SELECT m.id, e.name AS atual, m.final, (e.name = m.atual) AS nome_ok
FROM (VALUES
    (20451,  'NXFGTSL34-1','NXFGTSJ34-1'),
    (159526, 'NXFGTSI35-1','NXFGTSH35-1'),
    (1035060,'NXFGTSI35-3','NXFGTSH35-2'),
    (1047752,'NXFGTSI35-4','NXFGTSI35-1'),
    (1052807,'NXFGTSI35-5','NXFGTSI35-2'),
    (1057260,'NXFGTSI35-6','NXFGTSI35-3')
) m(id, atual, final)
JOIN entities e ON e.id = m.id
ORDER BY e.name;
-- E confirme que os alvos "livres" nao existem (deve voltar 0 linhas):
SELECT name FROM entities
WHERE name IN ('NXFGTSJ34-1','NXFGTSH35-1','NXFGTSH35-2');


-- ------------------------------------------------------------
-- PASSO 1 — APLICAR (transacao; ROLLBACK por padrao = NAO grava).
-- ------------------------------------------------------------
BEGIN;

-- 0) ORFA: arquivar (libera o nome 'NXFGTSI35-2' p/ o CR-05).
UPDATE entities
   SET name = 'ARCHIVED-NXFGTSI35-2-262653'
 WHERE id = 262653 AND name = 'NXFGTSI35-2';
UPDATE financial_accounts
   SET name = 'ARCHIVED-' || name || '-' || id
 WHERE name = 'assets pledged as collateral - NXFGTSI35-2';

-- 1) FASE 1: tudo -> nomes temporarios (libera os nomes atuais).
UPDATE entities          SET name = 'TMP-REN-'    || id
 WHERE id IN (20451,159526,1035060,1047752,1052807,1057260);
UPDATE financial_accounts SET name = 'TMP-REN-FA-' || id
 WHERE id IN (9632,9915,9917,9940,9972,10005);

-- 2) FASE 2: temporarios -> nomes finais (V1).
UPDATE entities SET name = CASE id
        WHEN 20451   THEN 'NXFGTSJ34-1'
        WHEN 159526  THEN 'NXFGTSH35-1'
        WHEN 1035060 THEN 'NXFGTSH35-2'
        WHEN 1047752 THEN 'NXFGTSI35-1'
        WHEN 1052807 THEN 'NXFGTSI35-2'
        WHEN 1057260 THEN 'NXFGTSI35-3'
    END
 WHERE id IN (20451,159526,1035060,1047752,1052807,1057260);
UPDATE financial_accounts SET name = 'assets pledged as collateral - ' || CASE id
        WHEN 9632  THEN 'NXFGTSJ34-1'
        WHEN 9915  THEN 'NXFGTSH35-1'
        WHEN 9917  THEN 'NXFGTSH35-2'
        WHEN 9940  THEN 'NXFGTSI35-1'
        WHEN 9972  THEN 'NXFGTSI35-2'
        WHEN 10005 THEN 'NXFGTSI35-3'
    END
 WHERE id IN (9632,9915,9917,9940,9972,10005);

-- POST-CHECK (ainda na transacao):
SELECT id, name FROM entities
 WHERE id IN (20451,159526,1035060,1047752,1052807,1057260,262653) ORDER BY name;
SELECT id, name FROM financial_accounts
 WHERE id IN (9632,9915,9917,9940,9972,10005) ORDER BY name;
-- Estes nomes antigos NAO podem mais existir (deve voltar 0 linhas):
SELECT name FROM entities
 WHERE name IN ('NXFGTSL34-1','NXFGTSI35-4','NXFGTSI35-5','NXFGTSI35-6');

ROLLBACK;   -- troque por COMMIT quando os checks acima estiverem certos.
-- COMMIT;


-- ============================================================
-- OPCIONAL — DELETAR a orfa em vez de arquivar (cascateia dependentes).
-- A orfa 262653 tem 9 valuations + 1 entity_type. Confira-os antes:
--   SELECT id, date::date, clean_price, last_valuation_flag
--   FROM valuations WHERE asset_id = 262653 ORDER BY date;
-- Se forem lixo, troque o bloco "0) ORFA: arquivar" acima por:
--   DELETE FROM valuations          WHERE asset_id  = 262653;   -- 9
--   DELETE FROM entity_types        WHERE entity_id = 262653;   -- 1
--   DELETE FROM financial_accounts  WHERE name = 'assets pledged as collateral - NXFGTSI35-2';
--   DELETE FROM entities            WHERE id = 262653;
-- ============================================================
