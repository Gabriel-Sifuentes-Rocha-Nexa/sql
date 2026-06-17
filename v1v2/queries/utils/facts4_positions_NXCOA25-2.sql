-- todas as posicoes onde o ATIVO e' o token NXCOA25-2
SELECT h.name AS holder, fa.name AS conta, tt.name AS txn, pp.lot_id,
       pp.total_quantity, pp.variation, pp.date, pp.last_position_flag AS vig,
       pp.block_id, pp.doc_id, pp.event_code
FROM positions pp
JOIN entities h ON h.id = pp.holder_id
LEFT JOIN financial_accounts fa ON fa.id = pp.financial_account_id
LEFT JOIN transaction_types tt ON tt.id = pp.transaction_type_id
WHERE pp.asset_id = (SELECT id FROM entities WHERE name = 'NXCOA25-2')
ORDER BY pp.date, pp.id
