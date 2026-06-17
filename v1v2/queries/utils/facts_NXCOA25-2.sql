-- Par serie<->token + quantidades para NXCOA25-2
SELECT 'token' AS tipo, e.id, e.name, t.issuance_amount::text AS qty, t.issuer_id
FROM entities e JOIN tokens t ON t.id = e.id
WHERE e.name = 'NXCOA25-2'
UNION ALL
SELECT 'serie(id-1)' AS tipo, e.id, e.name, ss.quantity::text AS qty, ss.issuer_id
FROM entities e JOIN securitization_series ss ON ss.id = e.id
WHERE e.id = (SELECT id-1 FROM entities WHERE name = 'NXCOA25-2')
