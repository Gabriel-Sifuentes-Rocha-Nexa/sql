-- V1: valuations do token NXCOF25-3 (aux 285e81f8...) em torno de 06-02/06-03
SELECT v.valuation_date, v.type, v.value, v.metadata
FROM valuations v
WHERE v.aux_id = '285e81f8-4114-4f5b-9749-38ddb5f093b8'
  AND v.valuation_date BETWEEN DATE '2025-05-29' AND DATE '2025-06-06'
ORDER BY v.valuation_date, v.type
