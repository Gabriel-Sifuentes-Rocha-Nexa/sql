-- V1: localizar o token NXCOF25-3 em securities
SELECT id, aux_id, name, full_name, code, type
FROM securities
WHERE full_name ILIKE '%NXCOF25-3%' OR name ILIKE '%NXCOF25-3%' OR code ILIKE '%NXCOF25-3%'
