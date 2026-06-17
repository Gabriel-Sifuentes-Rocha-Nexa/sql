-- facts genericos: conta de colateral -> subjacente + pernas de caixa. Uso: --ticker NXCOG26-3
SELECT pos.id, pos.block_id, fa.name AS conta, pos.asset_id, se.name AS asset_name,
       tt.name AS txn, pos.lot_id, pos.variation, pos.total_quantity,
       pos.last_position_flag AS vig, pos.date
FROM entities token_e
JOIN financial_accounts fa ON fa.name = 'assets pledged as collateral - ' || token_e.name
JOIN positions pos ON pos.financial_account_id = fa.id
LEFT JOIN entities se ON se.id = pos.asset_id
LEFT JOIN transaction_types tt ON tt.id = pos.transaction_type_id
WHERE token_e.name = ${ticker}
ORDER BY pos.date, pos.id
