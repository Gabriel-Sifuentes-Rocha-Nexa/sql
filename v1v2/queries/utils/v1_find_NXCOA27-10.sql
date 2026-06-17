-- V1: localizar NXCOA27-10
SELECT id, aux_id, name, full_name, code, type
FROM securities
WHERE full_name ILIKE '%NXCOA27-10%' OR name ILIKE '%NXCOA27-10%' OR code ILIKE '%NXCOA27-10%'
