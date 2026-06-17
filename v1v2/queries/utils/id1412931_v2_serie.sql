-- V2: serie suja (clean+accrued) do token NXCOA27-10 (asset 1412931)
SELECT v.id, v.date, v.clean_price, v.accrued_interest,
       (v.clean_price + COALESCE(v.accrued_interest,0)) AS dirty,
       v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v
WHERE v.asset_id=1412931
ORDER BY v.date, v.id
