-- Inserindo o Lucas
WITH new_person_entity AS (
    INSERT INTO public.entities (
        name, 
        source_id, 
        reference_table_id
    ) 
    VALUES (
        'LUCAS DANICEK BORGES',
        (SELECT id FROM public.sources WHERE name ILIKE 'internal'),
        (SELECT id FROM public.reference_tables WHERE name ILIKE 'contact_infos')
    )
    RETURNING id
)
INSERT INTO public.contact_infos (
    id, 
    document, 
    document_type
)
SELECT 
    id,                   -- Usa o mesmo ID da entity recém-criada
    '000.000.000-00',     -- SUBSTITUA PELO CPF REAL (Campo Obrigatório)
    'cpf'                -- document_type (Enum: cpf ou cnpj)
FROM new_person_entity;


select * from entities where name='LUCAS DANICEK BORGES'