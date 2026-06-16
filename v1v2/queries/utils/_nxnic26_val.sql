-- Últimas valuations do token NXNIC26-1 (id 2374) no V2
SELECT
    v.date,
    v.clean_price,
    v.accrued_interest,
    v.cash_flow,
    v.methodology_id,
    vm.name AS methodology,
    v.last_valuation_flag
FROM valuations v
LEFT JOIN valuation_methodologies vm ON vm.id = v.methodology_id
WHERE v.asset_id = 2374
ORDER BY v.date DESC, v.methodology_id
LIMIT 30;
