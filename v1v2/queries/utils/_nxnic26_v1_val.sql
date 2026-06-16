-- V1: valuations do security NXNIC26-1 (via aux_id)
SELECT
    v.valuation_date,
    v.value,
    v.type,
    v.metadata
FROM securities s
JOIN valuations v ON v.aux_id = s.aux_id
WHERE s.name = 'NXNIC26-1'
  AND v.valuation_date BETWEEN '2026-02-18' AND '2026-03-17'
ORDER BY v.valuation_date DESC, v.type
LIMIT 60;
