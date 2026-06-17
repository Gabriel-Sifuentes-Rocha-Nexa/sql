-- V2 PROD: que tipo de token e' o NXCOI26-2?
-- Mae (issuer) CR-CONSORTIUMS-N => token de CR; FIDC/securitization => tokenizacao direta (assets).
-- structure_name (token_structures) e strategy_name dao a classificacao explicita.
SELECT t.id,
       e.name              AS token,
       t.issuer_id,
       ie.name             AS issuer_mae,
       tstruct.structure_name,
       ts.strategy_name,
       t.issuance_amount
FROM tokens t
JOIN entities e            ON e.id = t.id
LEFT JOIN entities ie      ON ie.id = t.issuer_id
LEFT JOIN token_structures tstruct ON tstruct.id = t.structure_id
LEFT JOIN token_strategies ts      ON ts.id = t.strategy_id
WHERE e.name = 'NXCOI26-2'
