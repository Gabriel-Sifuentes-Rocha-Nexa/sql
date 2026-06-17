-- V1: posicoes do token NXCOF25-3 (qty vai a zero? available?) em torno de 06-01..06-05
SELECT p.position_date, p.amount, p.available, p.metadata
FROM positions p
WHERE p.asset_aux_id='285e81f8-4114-4f5b-9749-38ddb5f093b8'
  AND p.position_date BETWEEN DATE '2025-05-29' AND DATE '2025-06-06'
ORDER BY p.position_date
