-- Localizar NXNIC26* no V2: entidade + tipo
SELECT
    e.id          AS entity_id,
    e.name,
    e.reference_table_id,
    rt.name       AS ref_table
FROM entities e
LEFT JOIN reference_tables rt ON rt.id = e.reference_table_id
WHERE e.name ILIKE '%NXNIC26%'
ORDER BY e.name, e.id;
