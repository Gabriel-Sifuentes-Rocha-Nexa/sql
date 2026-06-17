-- operations ja usadas em histories + transaction_unit_price de baixas de token REDEMPTION existentes
SELECT 'hist_op' AS k, operation::text AS v, count(*)::text AS n, ''::text AS x
FROM histories GROUP BY operation
UNION ALL
SELECT 'tup_redemption', p.id::text, p.transaction_unit_price::text, tt.name
FROM positions p JOIN transaction_types tt ON tt.id=p.transaction_type_id
WHERE p.id IN (21078, 9950, 10980, 13952)
ORDER BY 1,2
