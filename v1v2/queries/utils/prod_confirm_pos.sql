-- PROD confirm: as positions alvo existem e sao as linhas certas?
SELECT a.name AS asset, p.id, p.block_id, p.date::text AS date, tt.name AS txn,
       p.variation::text AS variation, p.total_quantity::text AS total, p.last_position_flag AS vig
FROM positions p
JOIN entities a ON a.id = p.asset_id
LEFT JOIN transaction_types tt ON tt.id = p.transaction_type_id
WHERE p.id IN (9946,9947,9949,9950, 10979,10980, 2417649,2417650)
ORDER BY p.id
