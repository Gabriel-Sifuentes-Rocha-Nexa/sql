BEGIN;
-- =========================================================
-- 1. INSERT NA TABELA VALUATIONS
-- =========================================================
INSERT INTO public.valuations (
    date,
    asset_id,
    lot_id,
    methodology_id,
    clean_price,
    accrued_interest,
    indexer_id,
    indexer_percentage,
    spread_over_indexer,
    spread_over_cdi,
    spread_over_inflation,
    cash_flow,
    currency_id,
    created_at,
    last_valuation_flag
)
VALUES
-- LINHA 1: O "CDB" (Unitário) -> Definido para as 09:00
(
    '2025-04-16 09:00:00+00',
    (SELECT id FROM public.entities WHERE name = 'CDB4249DKQA' LIMIT 1),
    2, 
    (SELECT id FROM public.valuation_methodologies WHERE name = 'amortized_cost' LIMIT 1),
    0, 
    0, 
    (SELECT id FROM public.indexers WHERE name = 'PREFIXADO' LIMIT 1),
    1, 
    0, 
    0, 
    NULL, 
    109410.88758746, 
    (SELECT id FROM public.entities WHERE name = 'BRL' LIMIT 1),
    NOW(),
    false
),
-- LINHA 2: O "NXCDB" (Total) -> Definido para as 10:00
(
    '2025-04-16 10:00:00+00',
    (SELECT id FROM public.entities WHERE name = 'CDB4249DKQA' LIMIT 1),
    1, 
    (SELECT id FROM public.valuation_methodologies WHERE name = 'amortized_cost' LIMIT 1),
    0, 
    0, 
    (SELECT id FROM public.indexers WHERE name = 'PREFIXADO' LIMIT 1),
    1, 
    0, 
    0, 
    NULL, 
    105.50712400, 
    (SELECT id FROM public.entities WHERE name = 'BRL' LIMIT 1),
    NOW(),
    false
);
-- =========================================================
-- 2. INSERT NA TABELA POSITIONS (AS 4 PERNAS)
-- =========================================================
INSERT INTO public.positions (
    date, holder_id, asset_id, lot_id, financial_account_id, 
    transaction_type_id, variation, total_quantity, block_id, 
    event_code, payment_code, doc_id, last_position_flag, created_at
)
WITH constants AS (
    SELECT 
        (SELECT id FROM public.entities WHERE name = 'CDB4249DKQA' LIMIT 1) AS id_ativo_cdb,
        (SELECT id FROM public.entities WHERE name = 'NXCDBD25-1' LIMIT 1) AS id_ativo_token,
        (SELECT id FROM public.entities WHERE name = 'BRL' LIMIT 1) AS id_brl,
        (SELECT id FROM public.transaction_types WHERE name = 'REDEMPTION' LIMIT 1) AS id_tt_redemption,
        COALESCE((SELECT MAX(block_id) FROM public.positions), 0) AS max_block_id,
        109410.88758746 AS fluxo_caixa_cdb,     
        105.50712400 AS fluxo_caixa_token,      
        '2025-04-16 09:00:00+00'::timestamptz AS data_cdb,
        '2025-04-16 10:00:00+00'::timestamptz AS data_token,
        999999::bigint AS mock_doc_id
),
posicoes_cdb AS (
    SELECT p.holder_id, p.financial_account_id, p.total_quantity
    FROM public.positions p
    CROSS JOIN constants c
    WHERE p.asset_id = c.id_ativo_cdb AND p.lot_id = 2
      AND p.last_position_flag = true AND p.total_quantity > 0
),
posicoes_token AS (
    SELECT p.holder_id, p.financial_account_id, p.total_quantity
    FROM public.positions p
    CROSS JOIN constants c
    WHERE p.asset_id = c.id_ativo_token AND p.lot_id = 1
      AND p.last_position_flag = true AND p.total_quantity > 0
),
saldo_caixa_atual AS (
    SELECT p.holder_id, p.financial_account_id, p.total_quantity AS saldo_brl
    FROM public.positions p
    CROSS JOIN constants c
    WHERE p.asset_id = c.id_brl AND p.last_position_flag = true
)
SELECT 
    date, holder_id, asset_id, lot_id, financial_account_id, 
    transaction_type_id, variation, total_quantity, block_id, 
    event_code, payment_code, doc_id, 
    true AS last_position_flag, NOW() AS created_at
FROM (
    -- MOVIMENTO 1: Baixa CDB
    SELECT c.data_cdb AS date, p_cdb.holder_id, c.id_ativo_cdb AS asset_id, 2 AS lot_id, p_cdb.financial_account_id, c.id_tt_redemption AS transaction_type_id, -p_cdb.total_quantity AS variation, 0::decimal(18,6) AS total_quantity, (c.max_block_id + 1) AS block_id, NULL::text AS event_code, NULL::varchar(50) AS payment_code, c.mock_doc_id AS doc_id
    FROM posicoes_cdb p_cdb CROSS JOIN constants c
    UNION ALL
    -- MOVIMENTO 2: Entrada Caixa ref. CDB
    SELECT c.data_cdb AS date, p_cdb.holder_id, c.id_brl AS asset_id, 0 AS lot_id, p_cdb.financial_account_id, c.id_tt_redemption AS transaction_type_id, (p_cdb.total_quantity * c.fluxo_caixa_cdb) AS variation, (COALESCE(sc.saldo_brl, 0) + (p_cdb.total_quantity * c.fluxo_caixa_cdb)) AS total_quantity, (c.max_block_id + 1) AS block_id, NULL::text AS event_code, NULL::varchar(50) AS payment_code, c.mock_doc_id AS doc_id
    FROM posicoes_cdb p_cdb
    LEFT JOIN saldo_caixa_atual sc ON p_cdb.holder_id = sc.holder_id AND p_cdb.financial_account_id = sc.financial_account_id
    CROSS JOIN constants c
    UNION ALL
    -- MOVIMENTO 3: Baixa Token
    SELECT c.data_token AS date, pt.holder_id, c.id_ativo_token AS asset_id, 1 AS lot_id, pt.financial_account_id, c.id_tt_redemption AS transaction_type_id, -pt.total_quantity AS variation, 0::decimal(18,6) AS total_quantity, (c.max_block_id + 2) AS block_id, NULL::text AS event_code, NULL::varchar(50) AS payment_code, c.mock_doc_id AS doc_id
    FROM posicoes_token pt CROSS JOIN constants c
    UNION ALL
    -- MOVIMENTO 4: Saída Caixa ref. Token (travada na entrada)
    SELECT c.data_token AS date, pt.holder_id, c.id_brl AS asset_id, 0 AS lot_id, p_cdb.financial_account_id, c.id_tt_redemption AS transaction_type_id, -(p_cdb.total_quantity * c.fluxo_caixa_cdb) AS variation, COALESCE(sc.saldo_brl, 0) AS total_quantity, (c.max_block_id + 2) AS block_id, NULL::text AS event_code, NULL::varchar(50) AS payment_code, c.mock_doc_id AS doc_id
    FROM posicoes_token pt
    INNER JOIN posicoes_cdb p_cdb ON pt.holder_id = p_cdb.holder_id
    LEFT JOIN saldo_caixa_atual sc ON p_cdb.holder_id = sc.holder_id AND p_cdb.financial_account_id = sc.financial_account_id
    CROSS JOIN constants c
) AS movimentos;
-- =========================================================
-- 3. UPDATE: INATIVANDO AS POSIÇÕES ANTIGAS
-- =========================================================
UPDATE public.positions
SET 
    last_position_flag = false,
    updated_at = NOW()
WHERE last_position_flag = true
  -- Garante que não inative as linhas que acabamos de inserir
  AND date < '2025-04-16 09:00:00+00'::timestamptz
  AND (
      -- Inativa as posições antigas do CDB
      (asset_id = (SELECT id FROM public.entities WHERE name = 'CDB4249DKQA' LIMIT 1) AND lot_id = 2)
      OR 
      -- Inativa as posições antigas do Token
      (asset_id = (SELECT id FROM public.entities WHERE name = 'NXCDBD25-1' LIMIT 1) AND lot_id = 1)
      OR 
      -- Inativa o saldo de BRL apenas das contas contábeis que movimentaram caixa
      (asset_id = (SELECT id FROM public.entities WHERE name = 'BRL' LIMIT 1) 
       AND financial_account_id IN (
           SELECT financial_account_id FROM public.positions 
           WHERE asset_id = (SELECT id FROM public.entities WHERE name = 'CDB4249DKQA' LIMIT 1) AND lot_id = 2
       )
      )
  );
COMMIT;

