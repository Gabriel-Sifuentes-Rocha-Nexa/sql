-- V2: identificar asset_id 1412931 (nome + a que tabela tipada pertence)
SELECT 'entity' AS k, e.id::text AS id, e.name AS nome FROM entities e WHERE e.id=1412931
UNION ALL SELECT 'token', id::text, '' FROM tokens WHERE id=1412931
UNION ALL SELECT 'securitization_series', id::text, '' FROM securitization_series WHERE id=1412931
UNION ALL SELECT 'consortium', id::text, '' FROM consortiums WHERE id=1412931
UNION ALL SELECT 'fgts', id::text, '' FROM fgts WHERE id=1412931
UNION ALL SELECT 'ntni', id::text, '' FROM ntnis WHERE id=1412931
UNION ALL SELECT 'cdb', id::text, '' FROM cdbs WHERE id=1412931
UNION ALL SELECT 'securitization', id::text, '' FROM securitizations WHERE id=1412931
