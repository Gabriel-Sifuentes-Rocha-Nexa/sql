-- V1 (Supabase): pu (dirty) do token NXCOA27-10 e da mãe CR-Consorcio-43, 06-12..06-18
SELECT s.full_name, v.valuation_date, v.value AS pu, v.type
FROM valuations v
JOIN securities s ON s.aux_id = v.aux_id
WHERE s.full_name IN ('NXCOA27-10','CR-Consorcio-43')
  AND v.type = 'pu'
  AND v.valuation_date >= '2026-06-12' AND v.valuation_date < '2026-06-19'
ORDER BY s.full_name, v.valuation_date
