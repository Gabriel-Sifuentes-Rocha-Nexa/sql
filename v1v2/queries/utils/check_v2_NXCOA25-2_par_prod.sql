-- V2 PROD (:5003): existe "serie par" (asset_id 1684) p/ o token NXCOA25-2 (1685)?
-- Mostra nomes das duas entities e quaisquer valuations de 1684 na janela do resgate.
SELECT v.asset_id,
       a.name AS ativo,
       v.id,
       v.date,
       v.clean_price,
       v.accrued_interest,
       v.cash_flow,
       v.last_valuation_flag AS vig
FROM valuations v
JOIN entities a ON a.id = v.asset_id
WHERE v.asset_id = 1684
  AND v.date >= DATE '2025-01-13'
ORDER BY v.date, v.id
