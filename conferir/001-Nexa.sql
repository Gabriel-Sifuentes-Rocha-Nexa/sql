BEGIN;

-- [OPCIONAL] Se você já tinha inserido as versões antigas/zeradas, 
-- descomente as linhas abaixo para limpar antes de inserir os corretos:
-- DELETE FROM public.entities WHERE name IN ('NEXA DIGITAL ASSETS SA', 'FIDC NXCO', 'NEXA INC', 'NEXA FINANCE');


-- 1. Define os pares de Nome e CNPJ
WITH data_input (entity_name, entity_cnpj) AS (
    VALUES 
        ('NEXA DIGITAL ASSETS SA', '57230071000106'),
        ('FIDC NXCO',              '56125110000134'),
        ('NEXA FINANCE',           '54048859000108')
),
new_entities AS (
    INSERT INTO public.entities (
        name, 
        source_id, 
        reference_table_id
    )
    SELECT 
        d.entity_name,
        (SELECT id FROM public.sources WHERE name ILIKE 'internal'),       
        (SELECT id FROM public.reference_tables WHERE name ILIKE 'contact_infos') 
    FROM data_input d
    RETURNING id, name -- Retornamos o ID gerado E o nome para fazer o vínculo correto abaixo
)
INSERT INTO public.contact_infos (
    id, 
    document, 
    document_type, 
    created_at
)
SELECT 
    ne.id,
    d.entity_cnpj,
    'cnpj',
    NOW()
FROM new_entities ne
JOIN data_input d ON ne.name = d.entity_name;
COMMIT;

select * from entities where name in ('NEXA DIGITAL ASSETS SA',
'FIDC NXCO',             
'NEXA FINANCE'          )