-- V2: TODAS as posicoes do token 1412931 (achar integralizacao) + a conta de colateral
SELECT p.id, p.date, h.name AS holder, fa.name AS conta, tt.name AS txn,
       p.lot_id, p.variation, p.total_quantity, p.last_position_flag AS vig
FROM positions p
JOIN entities h ON h.id=p.holder_id
LEFT JOIN financial_accounts fa ON fa.id=p.financial_account_id
LEFT JOIN transaction_types tt ON tt.id=p.transaction_type_id
WHERE p.asset_id=1412931
   OR p.financial_account_id = (SELECT id FROM financial_accounts WHERE name='assets pledged as collateral - NXCOA27-10')
ORDER BY p.date, p.id
