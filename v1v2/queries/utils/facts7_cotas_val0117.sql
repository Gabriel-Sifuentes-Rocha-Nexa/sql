-- valuations das 3 cotas subjacentes em torno de 2025-01-17 (redimiram no dia 17?)
SELECT a.name AS cota, v.date, v.clean_price, v.accrued_interest, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE v.asset_id IN (1407, 1409, 1411)
  AND v.date::date BETWEEN DATE '2025-01-15' AND DATE '2025-01-22'
ORDER BY a.name, v.date
