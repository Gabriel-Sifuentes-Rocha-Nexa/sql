-- Localizar NXCOB26* no V1 (Supabase): security + tipo + estratégia + taxas
SELECT
    s.name,
    s.full_name,
    s.code,
    s.type,
    s.metadata->'internal'->>'strategy'                                   AS strategy,
    s.metadata->'internal'->>'indexador'                                  AS indexador,
    s.metadata->'internal'->>'tx_spread'                                  AS tx_spread,
    s.metadata->'internal'->>'tx_cessao'                                  AS tx_cessao,
    s.metadata->'internal'->'yield_correction'->>'tx_spread_yield_correction' AS tx_spread_yc,
    s.aux_id
FROM securities s
WHERE s.name ILIKE '%NXCOB26%'
   OR s.full_name ILIKE '%NXCOB26%'
   OR s.code ILIKE '%NXCOB26%'
ORDER BY s.full_name;
