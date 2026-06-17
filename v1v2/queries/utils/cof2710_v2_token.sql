-- V2: token NXCOA27-10 + mae (issuer) + quantidade
SELECT t.id, e.name AS token, t.issuer_id, ie.name AS issuer_mae, t.issuance_amount
FROM tokens t JOIN entities e ON e.id=t.id JOIN entities ie ON ie.id=t.issuer_id
WHERE e.name='NXCOA27-10'
