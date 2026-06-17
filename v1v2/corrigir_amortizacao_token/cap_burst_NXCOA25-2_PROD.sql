-- ============================================================================
-- cap_burst_NXCOA25-2_PROD.sql                       (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- Token NXCOA25-2 (asset 1685) — follow-up do refaz_redemption_NXCOA25-2_PROD.sql.
-- Depois que aquele fix moveu a redemption de 17->21/01 (16/06/2026), o batch diario
-- do engine re-accruou o buraco 18/19/20-01 e RECRIOU um burst de over-accrual:
--   accrued saltou 1.89543321 (17/01) -> 2.44256178 e ficou flat em 18/19/20,
--   deixando o dirty (clean+accrued) em 102.45469079 contra o TETO do V1 101.74022297.
-- (ids 30782053/54/55 — ids ~30,7M = inseridos APOS o fix; o resto do token e' ~260k.)
--
-- CORRECAO PEDIDA (Gabriel): NAO apagar as linhas — apenas CAPAR esse valor mais alto
-- no teto do V1. O burst esta todo no accrued (clean sempre foi 100.01212901, correto),
-- entao baixamos o accrued para que dirty = teto:
--   accrued_interest = 101.74022297 - 100.01212901 = 1.72809396  => dirty = 101.74022297
-- clean_price e cash_flow ficam inalterados. accrued nao e' coluna-chave do trigger de
-- last_valuation_flag, entao a vigente (21/01, clean 0) NAO muda.
-- AUDITORIA: cada linha -> histories (update) com o valor ANTIGO antes do UPDATE.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW — estado atual das 3 diarias-burst + vigente
SELECT 'antes' AS t, v.id, v.date::text,
       v.clean_price::text, v.accrued_interest::text,
       (v.clean_price + v.accrued_interest)::text AS dirty,
       v.last_valuation_flag AS vig
FROM valuations v
WHERE v.id IN (30782053,30782054,30782055,188248)
ORDER BY v.date, v.id;

-- (1) histories — log do valor ANTIGO das 3 linhas antes do UPDATE
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'update',
       'NXCOA25-2 capa burst over-accrual 18/19/20-01: accrued 2.44256178 -> 1.72809396 (dirty 102.45469079 -> teto V1 101.74022297); clean inalterado'
FROM valuations v WHERE v.id IN (30782053,30782054,30782055);

-- (2) UPDATE — capa o accrued p/ dirty = teto do V1 (clean fica 100.01212901)
UPDATE valuations
SET accrued_interest = 1.72809396
WHERE id IN (30782053,30782054,30782055);

-- (3) GUARDA
DO $$
DECLARE r record; n int; vdate timestamptz; vclean numeric; vcf numeric; vflag boolean;
BEGIN
  -- as 3 capadas: clean intacto, accrued 1.72809396, dirty = teto
  FOR r IN SELECT id, clean_price, accrued_interest,
                  (clean_price + accrued_interest) AS dirty
             FROM valuations WHERE id IN (30782053,30782054,30782055) LOOP
    IF round(r.clean_price,8) <> 100.01212901 THEN
      RAISE EXCEPTION 'id % clean=% (esperado 100.01212901)', r.id, r.clean_price; END IF;
    IF round(r.accrued_interest,8) <> 1.72809396 THEN
      RAISE EXCEPTION 'id % accrued=% (esperado 1.72809396)', r.id, r.accrued_interest; END IF;
    IF round(r.dirty,8) <> 101.74022297 THEN
      RAISE EXCEPTION 'id % dirty=% (esperado 101.74022297)', r.id, r.dirty; END IF;
  END LOOP;

  -- vigente NAO mudou: 188248, 21/01 20:00, clean 0, cash_flow 101.74022297, flag TRUE
  SELECT date, clean_price, cash_flow, last_valuation_flag
    INTO vdate, vclean, vcf, vflag
    FROM valuations WHERE id = 188248;
  IF vdate <> timestamptz '2025-01-21 20:00:00-03' THEN RAISE EXCEPTION 'vigente date mudou=%', vdate; END IF;
  IF vclean <> 0 THEN RAISE EXCEPTION 'vigente clean mudou=%', vclean; END IF;
  IF round(vcf,8) <> 101.74022297 THEN RAISE EXCEPTION 'vigente cash_flow mudou=%', vcf; END IF;
  IF NOT vflag THEN RAISE EXCEPTION 'vigente perdeu last_valuation_flag'; END IF;

  -- so' a vigente do token segue marcada (amortized_cost)
  SELECT count(*) INTO n FROM valuations
   WHERE asset_id=1685 AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND last_valuation_flag AND id <> 188248;
  IF n <> 0 THEN RAISE EXCEPTION 'ha % outra(s) valuation(s) marcada(s) como vigente', n; END IF;

  RAISE NOTICE 'OK NXCOA25-2: 18/19/20-01 capadas no teto 101.74022297 (clean 100.01212901 + accrued 1.72809396); vigente 21/01 intacta';
END $$;

-- (4) POST-CHECK — serie de 13/01 ate o resgate
SELECT v.id, v.date,
       v.clean_price, v.accrued_interest,
       (v.clean_price + v.accrued_interest) AS dirty,
       v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v
WHERE v.asset_id = 1685 AND v.date >= DATE '2025-01-13'
ORDER BY v.date, v.id;

SELECT operation, table_name, count(*) FROM histories
WHERE created_by='gabriel_sifuentes' AND description LIKE 'NXCOA25-2 capa burst%' GROUP BY operation, table_name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
