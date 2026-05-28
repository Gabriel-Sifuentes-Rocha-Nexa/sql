-- ============================================================
-- 5. Verificar se é fracionado
-- ------------------------------------------------------------
-- V1 ORIGINAL (Supabase, securities + metadata JSONB):
-- ------------------------------------------------------------
-- SELECT s.metadata->>'issuer' as issuer, e.metadata
-- FROM securities s
-- LEFT JOIN entities e ON e.aux_id = (s.metadata->>'issuer')::uuid
-- WHERE s.name = ${ticker} AND jsonb_array_length(e.metadata->'series') > 1
-- ------------------------------------------------------------
-- Resultado: retorna 0 ou 1 linha. Linha presente = fracionado (>1 série).
-- V1 retornava e.metadata (metadata completo do issuer) → em V2, os campos
-- da securitization do issuer + a contagem de séries.
-- ESCOPO: aplica-se a tokens com issuer-securitization (CR-style). Tokens de
-- tokenização direta (issuer = FIDC / NEXA DIGITAL ASSETS SA) retornam VAZIO,
-- pois `JOIN securitizations` / `JOIN securitization_series` não casam — pra
-- esses, "é fracionado?" não é definido (não existe estrutura de séries).
-- ============================================================
SELECT
    issuer_entity.id                        AS issuer,
    issuer_entity.name                      AS issuer_name,
    sec.document                            AS issuer_document,
    sec.issuance_number,
    sec.issuance_date,
    sua.name                                AS underlying_asset_name,
    sec_issuer_entity.name                  AS sec_issuer_name,
    trustee_entity.name                     AS trustee_name,
    sec.assignment_yield,
    sec.security_margin,
    COUNT(ss.id)                            AS series_count
FROM tokens tk
JOIN entities token_entity                  ON token_entity.id = tk.id
JOIN entities issuer_entity                 ON issuer_entity.id = tk.issuer_id
JOIN securitizations sec                    ON sec.id = issuer_entity.id
JOIN securitization_underlying_assets sua   ON sua.id = sec.underlying_asset_id
JOIN entities sec_issuer_entity             ON sec_issuer_entity.id = sec.issuer_id
JOIN entities trustee_entity                ON trustee_entity.id = sec.trustee_id
JOIN securitization_series ss               ON ss.issuer_id = issuer_entity.id
WHERE token_entity.name = 'NXFSC31-1'
GROUP BY
    issuer_entity.id, issuer_entity.name, sec.document, sec.issuance_number,
    sec.issuance_date, sua.name, sec_issuer_entity.name, trustee_entity.name,
    sec.assignment_yield, sec.security_margin
HAVING COUNT(ss.id) > 1;
