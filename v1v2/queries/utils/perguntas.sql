-- ============================================================
-- Perguntas de negócio — queries de apoio (V2 / engine)
-- Cada bloco é uma pergunta independente. Rode o bloco desejado.
-- ============================================================


-- ============================================================
-- Pergunta 1 — entity_id dos FIDCs (Crown, NXCO, NXFS, BWM, NXNI)
-- ------------------------------------------------------------
-- A maioria dos FIDCs é "mãe" do tipo `securitization` e se chama
-- "FIDC <COD>" (com espaço) — ex.: FIDC NXCO / FIDC NXFS / FIDC BWM.
-- MAS há idiossincrasias: nem todo FIDC está em `securitizations` e nem
-- todo um tem `entity_type`. O FIDC NXNI, p.ex., é a entidade
-- `NXNI_BWM_FIF_MM` (sem entity_type, só aparece como holder).
-- Por isso buscamos em TODAS as entidades, com um padrão por FIDC.
--
-- LEFT JOIN: FIDC que NÃO existir aparece com entity_id NULL (não some).
-- Resultado na cópia LOCAL:
--   FIDC NXCO  -> 16        (securitization, mãe)
--   FIDC NXFS  -> 1059150   (securitization, mãe)
--   FIDC BWM   -> 1387269   (securitization, mãe)
--   FIDC NXNI  -> 1387288   (série FIDC-NXNI-01-01-SINGLE; órfã: sem mãe registrada)
-- OBS: V1 chama a série de 'FIDC-NXNI-01-01-single-01' (minúsculo + sufixo -01);
--      no V2 é 'FIDC-NXNI-01-01-SINGLE' (sem -01). Por isso o padrão usa '%'.
-- ============================================================
WITH alvo(fidc_procurado, padrao) AS (
    VALUES
        ('FIDC NXCO',  'FIDC NXCO'),
        ('FIDC NXFS',  'FIDC NXFS'),
        ('FIDC BWM',   'FIDC BWM'),
        ('FIDC NXNI',  'FIDC-NXNI-01-01-single'))   -- V1 '...single-01' / V2 '...SINGLE' (1387288)
SELECT a.fidc_procurado,
       e.id   AS entity_id,
       e.name AS entity_name
FROM alvo a
LEFT JOIN entities e ON e.name ILIKE a.padrao
ORDER BY a.fidc_procurado;




select * from entities where name ilike '%nxni%'

select * from securitization_series where id =1387288


-- ------------------------------------------------------------
-- Catálogo de candidatos a FIDC/fundo (pra achar outros pelo codinome
-- real, ex.: o "Crown" quando entrar). Lista entidades que agem como
-- holder e que NÃO são ativo/token — ou seja, mães `securitization`
-- chamadas FIDC% e entidades sem entity_type (idiossincráticas).
-- ------------------------------------------------------------
SELECT DISTINCT
       e.id,
       e.name,
       etr.name AS entity_type
FROM entities e
JOIN positions p              ON p.holder_id = e.id
LEFT JOIN entity_types et     ON et.entity_id = e.id
LEFT JOIN entity_types_ref etr ON etr.id = et.ref_id
WHERE etr.name IS NULL                      -- sem tipo (FIF_MM, NEXA FINANCE, ...)
   OR (etr.name = 'securitization' AND e.name ILIKE 'FIDC%')
ORDER BY entity_type NULLS FIRST, e.name;

