-- ============================================================
-- CORRECAO DE HISTORICO. valuations.cash_flow mal lancado em eventos de
-- pagamento de securitization_series (mis-lancamento = -clean_price)
-- ------------------------------------------------------------
-- !!! SCRIPT DE ESCRITA. RODAR SOMENTE NA COPIA LOCAL DO ENGINE V2 !!!
-- !!! (127.0.0.1:5432/engine). NUNCA em producao nem no V1 (Supabase). !!!
--
-- O QUE FAZ: para cada linha-evento (cash_flow <> 0) de uma serie, EXCETO a
-- compra (1o evento), grava o cash_flow CORRETO = valor que de fato saiu do
-- instrumento naquele evento:
--
--     cash_flow_correto = dirty_before - dirty_after
--                       = (clean+accrued da vespera) - (clean+accrued do evento)
--
-- Sinal: POSITIVO no recebimento (amortizacao/resgate); a compra (negativo
-- legitimo, ev_rn = 1) NAO e' tocada. So altera linhas onde o valor gravado
-- diverge do correto (> 0.01), entao e' IDEMPOTENTE (re-rodar nao muda nada)
-- e nao mexe na CR-FGTS-30-01-SENIOR (resgate ja correto via API).
--
-- ESCOPO VALIDADO (read-only, 2026-06-08): 86 linhas, 17 series, 2025-07-08 a
-- 2026-05-15; todos os novos valores positivos (0.0174 a 94.40).
--
-- LAG por (asset_id, methodology_id, lot_id) -> pega o PU da vespera no MESMO
-- track de valuation. So mexe na coluna cash_flow; clean_price/accrued ficam
-- intactos (eles ja estao certos). cash_flow NAO e' mantido por trigger
-- (so last_valuation_flag e'), entao o UPDATE persiste.
-- ============================================================


-- ------------------------------------------------------------
-- PASSO 1 - PREVIEW (read-only): confira as 86 linhas antes de aplicar.
-- ------------------------------------------------------------
WITH base AS (
    SELECT v.id, v.asset_id, v.date, v.methodology_id, v.lot_id, v.cash_flow,
           ROUND(v.clean_price, 4)                            AS clean,
           (v.clean_price + COALESCE(v.accrued_interest, 0))  AS dirty_after,
           LAG(v.clean_price + COALESCE(v.accrued_interest, 0)) OVER w AS dirty_before
    FROM valuations v
    WHERE v.asset_id IN (SELECT id FROM securitization_series)
    WINDOW w AS (PARTITION BY v.asset_id, v.methodology_id, v.lot_id ORDER BY v.date, v.id)
),
events AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY asset_id, methodology_id, lot_id
                                 ORDER BY date, id) AS ev_rn
    FROM base
    WHERE cash_flow IS NOT NULL AND cash_flow <> 0
)
SELECT e.name AS series_name, ev.date::date AS date, ev.id,
       ev.clean                                AS clean_depois,
       ROUND(ev.cash_flow, 6)                  AS cash_flow_antigo,
       ROUND(ev.dirty_before - ev.dirty_after, 6) AS cash_flow_novo
FROM events ev
JOIN entities e ON e.id = ev.asset_id
WHERE ev.ev_rn > 1
  AND ev.dirty_before IS NOT NULL
  AND ABS(ev.cash_flow - (ev.dirty_before - ev.dirty_after)) > 0.01
ORDER BY e.name, ev.date;


-- ------------------------------------------------------------
-- PASSO 2 - APLICAR (transacional). Default ROLLBACK: rode o bloco, confira o
-- post-check (deve dar 0 linhas), e troque o ROLLBACK final por COMMIT.
-- ------------------------------------------------------------
BEGIN;

WITH base AS (
    SELECT v.id, v.asset_id, v.date, v.methodology_id, v.lot_id, v.cash_flow,
           (v.clean_price + COALESCE(v.accrued_interest, 0))  AS dirty_after,
           LAG(v.clean_price + COALESCE(v.accrued_interest, 0)) OVER w AS dirty_before
    FROM valuations v
    WHERE v.asset_id IN (SELECT id FROM securitization_series)
    WINDOW w AS (PARTITION BY v.asset_id, v.methodology_id, v.lot_id ORDER BY v.date, v.id)
),
events AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY asset_id, methodology_id, lot_id
                                 ORDER BY date, id) AS ev_rn
    FROM base
    WHERE cash_flow IS NOT NULL AND cash_flow <> 0
),
fix AS (
    SELECT id, (dirty_before - dirty_after) AS correct_cf
    FROM events
    WHERE ev_rn > 1
      AND dirty_before IS NOT NULL
      AND ABS(cash_flow - (dirty_before - dirty_after)) > 0.01
)
UPDATE valuations v
SET cash_flow = ROUND(fix.correct_cf, 8)
FROM fix
WHERE v.id = fix.id;
-- Esperado: UPDATE 86

-- POST-CHECK: a regra de conservacao nao pode mais ser violada. Deve dar 0 linhas.
WITH base AS (
    SELECT v.asset_id, v.date, v.id, v.cash_flow,
           (v.clean_price + COALESCE(v.accrued_interest, 0))  AS dirty_after,
           LAG(v.clean_price + COALESCE(v.accrued_interest, 0)) OVER w AS dirty_before
    FROM valuations v
    WHERE v.asset_id IN (SELECT id FROM securitization_series)
    WINDOW w AS (PARTITION BY v.asset_id, v.methodology_id, v.lot_id ORDER BY v.date, v.id)
),
ev AS (
    SELECT b.*, ROW_NUMBER() OVER (PARTITION BY asset_id, methodology_id, lot_id
                                   ORDER BY date, id) AS ev_rn,
           ABS(cash_flow - (dirty_before - dirty_after)) AS desvio
    FROM base b
    WHERE cash_flow IS NOT NULL AND cash_flow <> 0
)
SELECT COUNT(*) AS violacoes_restantes
FROM ev
WHERE ev_rn > 1 AND dirty_before IS NOT NULL AND desvio > 0.01;

-- Se violacoes_restantes = 0 e o UPDATE bateu 86: troque por COMMIT.
ROLLBACK;
-- COMMIT;
