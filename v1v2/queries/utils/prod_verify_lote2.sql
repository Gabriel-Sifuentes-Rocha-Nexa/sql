-- PROD verificacao pos-COMMIT (NXCOF25-3 1946 / NXCOE25-2 3032)
SELECT 'val_vigente' AS tipo, a.name AS token, v.date::text AS dt, v.clean_price::text AS clean, v.cash_flow::text AS cf
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1946,3032) AND v.last_valuation_flag
UNION ALL
SELECT 'token_pos_vig', a.name, p.date::text, p.total_quantity::text, ''
FROM positions p JOIN entities a ON a.id=p.asset_id JOIN financial_accounts fa ON fa.id=p.financial_account_id
WHERE p.asset_id IN (1946,3032) AND fa.name='token investments' AND p.last_position_flag
UNION ALL
SELECT 'brl_colateral_vig', t.nome, p.date::text, p.total_quantity::text, ''
FROM positions p
JOIN financial_accounts fa ON fa.id=p.financial_account_id
JOIN (VALUES ('assets pledged as collateral - NXCOF25-3','NXCOF25-3'),
             ('assets pledged as collateral - NXCOE25-2','NXCOE25-2')) AS t(conta,nome) ON t.conta=fa.name
WHERE p.asset_id=2 AND p.last_position_flag
UNION ALL
SELECT 'fantasmas_apos0602', a.name, count(*)::text, '', ''
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1946,3032) AND v.date::date>'2025-06-02'
GROUP BY a.name
ORDER BY 1,2
