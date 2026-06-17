-- V2 PROD (:5003): confirma os histories gravados pelo cap do burst do NXCOA25-2.
SELECT id, created_by, table_name, operation,
       old_value->>'id'               AS old_id,
       old_value->>'date'             AS old_date,
       old_value->>'accrued_interest' AS old_accrued,
       description
FROM histories
WHERE created_by = 'gabriel_sifuentes'
  AND description LIKE 'NXCOA25-2 capa burst%'
ORDER BY id
