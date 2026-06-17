-- PROD verificacao pos-COMMIT: NXCOF25-3 (2 amorts) + NXCOF25-2 (preco 01-16)
SELECT 'COF3 val 06-02/03' AS k, v.date::text AS dt, v.clean_price::text AS clean, v.cash_flow::text AS cf
FROM valuations v WHERE v.asset_id=1946 AND v.date::date BETWEEN '2025-06-02' AND '2025-06-03'
UNION ALL
SELECT 'COF3 token_pos_vig', p.date::text, p.total_quantity::text, ''
FROM positions p JOIN financial_accounts fa ON fa.id=p.financial_account_id
WHERE p.asset_id=1946 AND fa.name='token investments' AND p.last_position_flag
UNION ALL
SELECT 'COF3 brl_colateral_vig', p.date::text, p.total_quantity::text, ''
FROM positions p JOIN financial_accounts fa ON fa.id=p.financial_account_id
WHERE p.asset_id=2 AND fa.name='assets pledged as collateral - NXCOF25-3' AND p.last_position_flag
UNION ALL
SELECT 'COF2 preco_0116', v.date::text, v.clean_price::text, v.last_valuation_flag::text
FROM valuations v WHERE v.asset_id=1938 AND v.date::date='2025-01-16'
ORDER BY 1, 2
