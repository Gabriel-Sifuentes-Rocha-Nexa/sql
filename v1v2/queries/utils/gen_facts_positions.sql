-- facts genericos: posicoes onde o ATIVO e' o token. Uso: --ticker NXCOG26-3
SELECT pp.id, pp.block_id, h.name AS holder, fa.name AS conta, tt.name AS txn,
       pp.lot_id, pp.variation, pp.total_quantity, pp.date,
       pp.last_position_flag AS vig, pp.doc_id
FROM positions pp
JOIN entities h ON h.id = pp.holder_id
LEFT JOIN financial_accounts fa ON fa.id = pp.financial_account_id
LEFT JOIN transaction_types tt ON tt.id = pp.transaction_type_id
WHERE pp.asset_id = (SELECT id FROM entities WHERE name = ${ticker})
ORDER BY pp.date, pp.id
