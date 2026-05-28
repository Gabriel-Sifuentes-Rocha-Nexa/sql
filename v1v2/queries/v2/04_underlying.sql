-- ============================================================
-- 4. Obter underlying (token)
-- ------------------------------------------------------------
-- V1 ORIGINAL (Supabase, securities + metadata JSONB):
-- ------------------------------------------------------------
-- SELECT e.metadata->>'spv_underlyings' AS underlying
-- FROM securities s
-- JOIN entities e ON e.aux_id = (s.metadata->>'issuer')::uuid
-- WHERE (s.name = ${ticker} OR s.full_name = ${ticker})
--   AND s.type = 'token'
-- LIMIT 1
-- ------------------------------------------------------------
-- ESCOPO: aplica-se a tokens com issuer-securitization (CR-style). Tokens de
-- tokenização direta (issuer = FIDC / NEXA DIGITAL ASSETS SA) retornam VAZIO,
-- pois o `JOIN securitizations` não casa. Equivale ao V1, que lia o campo
-- `metadata->>'spv_underlyings'` (específico de SPV).
-- ============================================================
SELECT
    sua.name                                AS underlying,                 -- spv_underlyings (V1)
    token_entity.name                       AS token_name,
    ts.strategy_name,
    tstruct.structure_name,
    -- SPV emissor (securitization)
    spv_entity.name                         AS issuer_name,
    sec.document                            AS issuer_document,
    sec.issuance_number,
    sec.issuance_date,
    sec_issuer_entity.name                  AS sec_issuer_name,
    trustee_entity.name                     AS trustee_name
FROM tokens tk
JOIN entities token_entity                  ON token_entity.id = tk.id
JOIN securitizations sec                    ON sec.id = tk.issuer_id
JOIN entities spv_entity                    ON spv_entity.id = sec.id
JOIN securitization_underlying_assets sua   ON sua.id = sec.underlying_asset_id
JOIN entities sec_issuer_entity             ON sec_issuer_entity.id = sec.issuer_id
JOIN entities trustee_entity                ON trustee_entity.id = sec.trustee_id
LEFT JOIN token_strategies ts               ON ts.id = tk.strategy_id
LEFT JOIN token_structures tstruct          ON tstruct.id = tk.structure_id
WHERE token_entity.name = 'NXFGTSB31-3'
LIMIT 1;
