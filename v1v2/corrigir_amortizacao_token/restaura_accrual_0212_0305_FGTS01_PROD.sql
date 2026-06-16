-- ============================================================================
-- restaura_accrual_0212_0305_FGTS01_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- Conserta um over-delete: eu apaguei valuations > 02-11 09:00 (ate 06-11), mas a
-- accrual legitima 02-12 -> 03-05 (pre-amort do proximo evento) nao devia sair.
-- Restaura do `histories` SO essa janela (02-12 00:00 -> 03-05 00:00), serie + token,
-- reconstruindo as linhas a partir do old_value (jsonb). As de 03-06 -> 06-11 (sem
-- amort, erradas) ficam apagadas. Resultado: serie/token terminam no pre-amort 03-05 00:00.
--
-- Fonte: as 240 linhas que EU gravei em histories ao apagar (operation='delete',
-- description 'apaga valuations dailies extras ...'). Restaura ids/valores originais.
-- (Nao loga em histories: o enum so tem delete/update; isto e' um revert do delete ja logado.)
-- DRY-RUN: BEGIN..ROLLBACK; trocar por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW — o que sera restaurado (janela 02-12..03-05), por ativo
SELECT (h.old_value->>'asset_id')::int AS asset_id,
       count(*) AS linhas_a_restaurar,
       min((h.old_value->>'date')::timestamptz) AS menor,
       max((h.old_value->>'date')::timestamptz) AS maior
FROM histories h
WHERE h.created_by='gabriel_sifuentes' AND h.operation='delete' AND h.table_name='valuations'
  AND h.description LIKE 'apaga valuations dailies extras%'
  AND (h.old_value->>'date')::timestamptz >  timestamptz '2026-02-11 09:00:00-03'
  AND (h.old_value->>'date')::timestamptz <= timestamptz '2026-03-05 00:00:00-03'
GROUP BY 1 ORDER BY 1;

-- (1) RESTORE: reinsere as linhas da janela
INSERT INTO valuations
SELECT (jsonb_populate_record(null::valuations, h.old_value)).*
FROM histories h
WHERE h.created_by='gabriel_sifuentes' AND h.operation='delete' AND h.table_name='valuations'
  AND h.description LIKE 'apaga valuations dailies extras%'
  AND (h.old_value->>'date')::timestamptz >  timestamptz '2026-02-11 09:00:00-03'
  AND (h.old_value->>'date')::timestamptz <= timestamptz '2026-03-05 00:00:00-03';

-- (2) GUARDA: serie/token terminam no pre-amort 03-05 00:00, sincronizados, sem evento em 03-05
DO $$
DECLARE ns int; nt int; ms timestamptz; mt timestamptz; ev int;
BEGIN
  SELECT count(*), max(date) INTO ns, ms FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='CR-FGTS-01-01-SINGLE');
  SELECT count(*), max(date) INTO nt, mt FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='NXFGTSJ34-1');
  IF ms <> timestamptz '2026-03-05 00:00:00-03' OR mt <> timestamptz '2026-03-05 00:00:00-03'
     THEN RAISE EXCEPTION 'max(date) != pre-amort 03-05 00:00 (serie=%, token=%)', ms, mt; END IF;
  IF ns <> nt THEN RAISE EXCEPTION 'serie (%) e token (%) dessincronizados', ns, nt; END IF;
  SELECT count(*) INTO ev FROM valuations
   WHERE asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1'))
     AND date::date='2026-03-05' AND cash_flow <> 0;
  IF ev > 0 THEN RAISE EXCEPTION 'apareceu evento (cash_flow<>0) em 03-05 — nao deveria (so pre-amort)'; END IF;
  RAISE NOTICE 'OK: serie e token com % linhas, terminando no pre-amort 03-05 00:00 (sem evento)', ns;
END $$;

-- (3) POST-CHECK: estado + o pre-amort de 03-05
SELECT a.name AS ativo, count(*) AS n, max(v.date) AS maior FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE a.name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1') GROUP BY a.name;

SELECT a.name, v.date, v.clean_price, v.accrued_interest, v.cash_flow, v.last_valuation_flag
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE a.name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1') AND v.date::date='2026-03-05' ORDER BY a.name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
