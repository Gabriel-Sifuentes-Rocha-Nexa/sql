-- V1: metadados do security NXNIC26-1
SELECT
    s.name,
    s.full_name,
    s.code,
    s.type,
    s.metadata
FROM securities s
WHERE s.name = 'NXNIC26-1';
