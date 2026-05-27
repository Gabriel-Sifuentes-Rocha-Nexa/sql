WITH new_entity AS (
    INSERT INTO public.entities (
        name, 
        source_id, 
        reference_table_id
    ) 
    VALUES (
        'CANOPUS ADMINISTRADORA DE CONSORCIOS SA',
        (SELECT id FROM public.sources WHERE name ILIKE 'internal'),
        (SELECT id FROM public.reference_tables WHERE name ILIKE 'contact_infos')
    )
    RETURNING id
)
INSERT INTO public.contact_infos (
    id, 
    document, 
    document_type,
    created_at
)
SELECT 
    id,                  -- ID gerado na tabela entities
    '68318800000000',    -- Documento solicitado
    'cnpj',              
    NOW()
FROM new_entity;