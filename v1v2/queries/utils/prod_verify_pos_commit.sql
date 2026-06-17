-- PROD verificacao pos-COMMIT
SELECT 'val_vigente' AS tipo, a.name AS token, v.date::text AS dt,
       v.clean_price::text AS clean, v.cash_flow::text AS cash_flow
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE v.asset_id IN (1685,762,3256) AND v.last_valuation_flag
UNION ALL
SELECT 'token_pos_vigente', a.name, p.date::text, p.total_quantity::text, ''
FROM positions p JOIN entities a ON a.id = p.asset_id
JOIN financial_accounts fa ON fa.id = p.financial_account_id
WHERE p.asset_id IN (1685,762,3256) AND fa.name = 'token investments' AND p.last_position_flag
UNION ALL
SELECT 'lixo_burst_restante', 'ids 260144..5961251', count(*)::text, '', ''
FROM valuations WHERE id IN (260144,260145,260146,260147,260148,5956654,5961251)
ORDER BY 1, 2
