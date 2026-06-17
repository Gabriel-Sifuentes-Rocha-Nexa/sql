-- V2 PROD (:5003): estado atual do token NXCOA25-2 (asset 1685) em torno do resgate.
-- dirty = clean_price + accrued_interest (p/ comparar com o pu do V1).
SELECT v.id,
       v.date,
       m.name AS metodologia,
       v.clean_price,
       v.accrued_interest,
       (v.clean_price + v.accrued_interest) AS dirty,
       v.cash_flow,
       v.last_valuation_flag AS vig
FROM valuations v
LEFT JOIN valuation_methodologies m ON m.id = v.methodology_id
WHERE v.asset_id = 1685
  AND v.date >= DATE '2025-01-13'
ORDER BY v.date, v.id