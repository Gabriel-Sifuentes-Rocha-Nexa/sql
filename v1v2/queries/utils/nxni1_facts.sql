-- token NXNIB25-1: id, quantidade, issuer (mae)
SELECT e.id, e.name, t.issuance_amount::text AS qty, t.issuer_id,
       (SELECT name FROM entities WHERE id = t.issuer_id) AS issuer_name
FROM entities e JOIN tokens t ON t.id = e.id
WHERE e.name = 'NXNIB25-1'
