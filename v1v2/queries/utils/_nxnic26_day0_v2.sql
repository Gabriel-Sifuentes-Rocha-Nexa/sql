-- V2: primeiras valuations do token 2374 (dia 0 / emissao)
SELECT
    v.date,
    v.clean_price,
    v.accrued_interest,
    (v.clean_price + v.accrued_interest) AS pu_total,
    v.cash_flow,
    vm.name AS methodology
FROM valuations v
LEFT JOIN valuation_methodologies vm ON vm.id = v.methodology_id
WHERE v.asset_id = 2374
ORDER BY v.date ASC
LIMIT 15;
