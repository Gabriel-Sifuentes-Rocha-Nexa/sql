WITH new_entity AS (
    INSERT INTO public.entities (
        name, 
        source_id, 
        reference_table_id
    ) 
    VALUES (
        'CONSORCIEI PARTICIPACOES SA',
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
    '00000000000000',    -- CNPJ zerado
    'cnpj',              -- Tipo de documento
    NOW()
FROM new_entity;