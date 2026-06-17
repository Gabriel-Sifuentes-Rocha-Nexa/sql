-- Cobertura do banco em torno de 2025-01-16
SELECT
  (SELECT count(*) FROM valuations WHERE date::date = DATE '2025-01-16') AS vals_no_dia,
  (SELECT count(*) FROM positions  WHERE date::date = DATE '2025-01-16') AS pos_no_dia,
  (SELECT min(date) FROM valuations) AS min_val_date,
  (SELECT max(date) FROM valuations) AS max_val_date,
  (SELECT count(DISTINCT name) FROM transaction_types WHERE name = 'AMORTIZATION') AS tt_amort_existe
