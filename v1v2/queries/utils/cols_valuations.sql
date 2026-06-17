-- colunas exatas de valuations (ordinal) p/ montar INSERT completo
SELECT ordinal_position AS pos, column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='public' AND table_name='valuations'
ORDER BY ordinal_position
