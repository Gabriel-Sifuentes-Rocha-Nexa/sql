-- V1 (Supabase, read-only): PU do token NXCOA25-2 nas datas do resgate.
-- Verdade p/ comparar com o V2 PROD (clean_price+accrued). Mostra os ultimos pu.
SELECT s.full_name,
       v.valuation_date,
       v.value AS pu,
       v.type,
       v.metadata->>'related_event' AS related_event
FROM securities s
JOIN valuations v ON v.aux_id = s.aux_id
WHERE s.full_name = 'NXCOA25-2'
  AND v.type = 'pu'
  AND v.valuation_date >= DATE '2025-01-10'
ORDER BY v.valuation_date