-- ============================================================
-- util. Preços dos indexadores (CDI, IPCA, PTAX) no Engine V2
-- Convenções gerais: ver ../../CLAUDE.md
-- ------------------------------------------------------------
-- CONTEXTO (migração V1 -> V2):
--   No V1 cada indexador era um único `aux_id` (UUID) e o preço saía
--   por esse aux_id (valuations/quotes do security do indexador):
--     AUX_ID_CDI  = 2c7ef6dc-beb9-4d99-b6db-4575b6ca0a23
--     AUX_ID_IPCA = fb0eb728-1ee7-4820-af90-71abeb80066d
--     AUX_ID_PTAX = 82f4178b-3a24-48eb-afc8-4b32c7a910ef
--
--   No V2 NÃO existe um "aux_id equivalente" único. O modelo é tipado e
--   o valor de cada indexador mora em uma tabela diferente conforme a natureza:
--
--   | Indexador | Valor mora em   | Chave de acesso                                            |
--   |-----------|-----------------|------------------------------------------------------------|
--   | CDI       | curves          | curve_id = entities.id da entidade 'CDI'   (série diária)   |
--   | IPCA      | curves          | curve_id = entities.id da entidade 'IPCA'  (série mensal/VNA)|
--   | PTAX      | exchange_rates  | USD->BRL + methodology 'ptax_dollar' (NÃO é curva)          |
--
--   `indexers` é só o LOOKUP de tipo (FK `indexer_id` em fgts/consortiums/tokens/
--   securitization_series/valuations). NÃO guarda preço. Os nomes lá são:
--     CDI=2, IPCA=3, DOLLAR_PTAX=11 (e PREFIXADO, INPC, IGP-M, TR, IPC-FIPE,
--     SELIC, SOFR, EQUITY, INCC, INFLATION).
--
-- ARMADILHA dos IDs: em V2 os ids são SERIAL (específicos do ambiente), ao
--   contrário do aux_id UUID do V1 (estável entre ambientes). RESOLVA SEMPRE
--   POR NOME (como abaixo); não chumbe inteiros no código.
--   IDs observados na cópia LOCAL do V2 (engine @127.0.0.1, dados até 2026-05-29):
--     entities 'CDI'  -> id 12   |  entities 'IPCA' -> id 13   (= curves.curve_id)
--     currencies: USD (issuer 'EUA') = 1 ; BRL (issuer 'BRA') = 2
--     valuation_methodologies 'ptax_dollar' = 6
--
-- OBS curva vs forward: 'CDI'/'IPCA' aqui são a série SPOT (1 parâmetro). As
--   curvas a termo (ETTJ) são outras entidades: CURVA_DI_PRE_B3, CURVA_DI_IPCA_B3,
--   CURVA_*_ANBIMA — use-as se precisar de estrutura a termo, não do valor corrente.
-- ============================================================


-- ------------------------------------------------------------
-- 0) "Qual é o id?" — resolve os identificadores V2 por NOME
-- ------------------------------------------------------------
-- tipo do indexador (lookup; não tem preço)
SELECT id, name FROM indexers
WHERE name IN ('CDI', 'IPCA', 'DOLLAR_PTAX')
ORDER BY id;

-- entidades-curva que guardam a SÉRIE de valores (curves.curve_id = entities.id)
SELECT id, name FROM entities
WHERE name IN ('CDI', 'IPCA')
ORDER BY name;

-- par de moedas do PTAX (currencies não tem `name`; vem do currency_issuer)
SELECT cur.id, ci.name AS issuer
FROM currencies cur
JOIN currency_issuers ci ON ci.id = cur.currency_issuer_id
WHERE ci.name IN ('EUA', 'BRA')
ORDER BY ci.name;

-- metodologia do PTAX
SELECT id, name FROM valuation_methodologies WHERE name = 'ptax_dollar';


-- ------------------------------------------------------------
-- 1) CDI — últimos valores (série diária em `curves`)
-- ------------------------------------------------------------
-- value = taxa CDI a.a. em coeficiente (ex.: 0.144 = 14,4% a.a.)
SELECT
    e.name              AS indexer,
    c.date,
    c.parameter,
    pt.name             AS parameter_type,
    c.value
FROM curves c
JOIN entities e            ON e.id = c.curve_id
LEFT JOIN parameter_types pt ON pt.id = c.parameter_type_id
WHERE e.name = 'CDI'
ORDER BY c.date DESC
LIMIT 10;


-- ------------------------------------------------------------
-- 2) IPCA — últimos valores (série mensal em `curves`, VNA)
-- ------------------------------------------------------------
-- value = VNA (Valor Nominal Atualizado / nível do índice), não percentual
SELECT
    e.name              AS indexer,
    c.date,
    c.parameter,
    pt.name             AS parameter_type,
    c.value
FROM curves c
JOIN entities e            ON e.id = c.curve_id
LEFT JOIN parameter_types pt ON pt.id = c.parameter_type_id
WHERE e.name = 'IPCA'
ORDER BY c.date DESC
LIMIT 10;


-- ------------------------------------------------------------
-- 3) PTAX — últimos valores (USD->BRL em `exchange_rates`)
-- ------------------------------------------------------------
-- value = BRL por 1 USD (PTAX venda do BCB)
SELECT
    num_i.name          AS de,
    den_i.name          AS para,
    er.date::date       AS date,
    er.value,
    m.name              AS methodology,
    s.name              AS source
FROM exchange_rates er
JOIN currencies num_c       ON num_c.id = er.numerator_id
JOIN currency_issuers num_i ON num_i.id = num_c.currency_issuer_id
JOIN currencies den_c       ON den_c.id = er.denominator_id
JOIN currency_issuers den_i ON den_i.id = den_c.currency_issuer_id
JOIN valuation_methodologies m ON m.id = er.methodology_id
LEFT JOIN sources s         ON s.id = er.source_id
WHERE num_i.name = 'EUA'        -- USD
  AND den_i.name = 'BRA'        -- BRL
  AND m.name = 'ptax_dollar'
ORDER BY er.date DESC
LIMIT 10;


-- ------------------------------------------------------------
-- 4) Snapshot — último valor de cada indexador numa só consulta
-- ------------------------------------------------------------
(
    SELECT DISTINCT ON (e.name)
        e.name              AS indexer,
        c.date::date        AS date,
        c.value,
        pt.name             AS unit
    FROM curves c
    JOIN entities e            ON e.id = c.curve_id
    LEFT JOIN parameter_types pt ON pt.id = c.parameter_type_id
    WHERE e.name IN ('CDI', 'IPCA')
    ORDER BY e.name, c.date DESC
)
UNION ALL
(
    SELECT
        'DOLLAR_PTAX'       AS indexer,
        er.date::date       AS date,
        er.value,
        'BRL/USD'           AS unit
    FROM exchange_rates er
    JOIN currencies num_c       ON num_c.id = er.numerator_id
    JOIN currency_issuers num_i ON num_i.id = num_c.currency_issuer_id
    JOIN currencies den_c       ON den_c.id = er.denominator_id
    JOIN currency_issuers den_i ON den_i.id = den_c.currency_issuer_id
    JOIN valuation_methodologies m ON m.id = er.methodology_id
    WHERE num_i.name = 'EUA' AND den_i.name = 'BRA' AND m.name = 'ptax_dollar'
    ORDER BY er.date DESC
    LIMIT 1
)
ORDER BY indexer;

-- ------------------------------------------------------------
-- RESULTADO (cópia LOCAL do V2, dados até 2026-05-29):
--   CDI         | 2026-05-29 | 0.144000     | coefficient  (= 14,4% a.a.)
--   IPCA        | 2026-04-30 | 7596.090000  | VNA          (nível do índice; série mensal)
--   DOLLAR_PTAX | 2026-05-29 | 5.056900     | BRL/USD
-- ============================================================
