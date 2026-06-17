-- TODAS as posicoes do dia 2025-01-17 ligadas ao token/cotas/conta de colateral (ids + block_id)
SELECT pp.id, pp.block_id, pp.date, h.name AS holder, a.name AS asset,
       fa.name AS conta, tt.name AS txn, pp.lot_id, pp.variation, pp.total_quantity,
       pp.last_position_flag AS vig, pp.doc_id
FROM positions pp
JOIN entities a ON a.id = pp.asset_id
JOIN entities h ON h.id = pp.holder_id
LEFT JOIN financial_accounts fa ON fa.id = pp.financial_account_id
LEFT JOIN transaction_types tt ON tt.id = pp.transaction_type_id
WHERE pp.date::date = DATE '2025-01-17'
  AND ( pp.asset_id IN (1685, 1407, 1409, 1411)
        OR pp.financial_account_id = (SELECT id FROM financial_accounts WHERE name = 'assets pledged as collateral - NXCOA25-2') )
ORDER BY pp.date, pp.id
