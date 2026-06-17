-- V2: serie (1412930) e token (1412931) lado a lado, 06-12..06-18 (dirty + ids)
SELECT a.name AS ativo, v.id, v.date, v.clean_price, v.accrued_interest,
       (v.clean_price + COALESCE(v.accrued_interest,0)) AS dirty, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1412930,1412931) AND v.date::date BETWEEN '2026-06-12' AND '2026-06-18'
ORDER BY a.name, v.date, v.id
