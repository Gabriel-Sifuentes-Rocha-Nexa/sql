-- ============================================================
-- UTIL. Cash flow de evento INCONSISTENTE em valuations (series de CR)
-- ------------------------------------------------------------
-- Detecta linhas de `valuations` (asset_id = securitization_series) em que o
-- engine V2 lancou um `cash_flow` que NAO bate com a queda do PU no evento.
--
-- REGRA (conservacao de valor): o cash_flow e' dinheiro que SAIU do instrumento;
-- so e' legitimo se o PU caiu na mesma proporcao. Comparar |cash_flow| com a
-- QUEDA do PU sujo entre a vespera e a linha-evento:
--
--   queda_pu = PU_sujo(vespera) - PU_sujo(evento)      -- valor que de fato saiu
--   excesso  = |cash_flow| - GREATEST(queda_pu, 0)
--
--   * cash pequeno em relacao ao PU            -> excesso pequeno  -> OK
--   * cash grande mas PU cai muito (ex resgate)-> excesso ~0       -> OK
--   * cash GRANDE e PU CONTINUA GRANDE         -> excesso GRANDE   -> ERRO
--     (saida de caixa sem o instrumento abrir mao do valor)
--
-- O bug observado no V2: em cada amortizacao a linha-evento grava
-- `cash_flow = -clean_price` (espelha o preco) em vez do principal(+cupom)
-- devolvido naquela data. Logo |cash_flow| ~ PU inteiro enquanto o PU mal cai.
--
-- A 1a valuation (a COMPRA/integralizacao, cash_flow = -100, PU surge em 100)
-- e' negativo LEGITIMO e fica de fora do flag (ev_rn = 1 => 'compra').
--
-- CONTROLE (nao deve flagar): CR-FGTS-30-01-SENIOR — resgate booado correto
-- (clean->0, cash_flow +101.42, excesso 0). Mesma metodologia (amortized_cost)
-- que as series com erro, provando que -clean_price e' mis-booking, nao convencao.
--
-- USO: roda p/ todas as series. Limiar do flag em `params.limiar_pu` (em pontos
-- de PU, base 100). Para uma serie so, descomente o filtro em `base`.
-- ============================================================
WITH params AS (
    SELECT 1.0::numeric AS limiar_pu          -- excesso (em PU) a partir do qual marca ERRO
),
base AS (
    -- todas as valuations das series + PU sujo/limpo da linha imediatamente anterior
    SELECT
        v.asset_id, v.date, v.id,
        v.clean_price                                              AS clean_after,
        (v.clean_price + COALESCE(v.accrued_interest, 0))          AS dirty_after,
        v.cash_flow,
        LAG(v.clean_price) OVER w                                  AS clean_before,
        LAG(v.clean_price + COALESCE(v.accrued_interest, 0)) OVER w AS dirty_before
    FROM valuations v
    WHERE v.asset_id IN (SELECT id FROM securitization_series)
    -- AND v.asset_id = (SELECT id FROM entities WHERE name = 'CR-FGTS-01-01-SINGLE')  -- <- 1 serie so
    WINDOW w AS (PARTITION BY v.asset_id ORDER BY v.date, v.id)
),
ev AS (
    -- so as linhas-evento (cash_flow <> 0); enumera p/ isolar a compra (ev_rn = 1)
    SELECT
        b.*,
        ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY date, id)  AS ev_rn,
        (dirty_before - dirty_after)                                 AS queda_pu,
        ABS(cash_flow) - GREATEST(dirty_before - dirty_after, 0)     AS excesso
    FROM base b
    WHERE cash_flow IS NOT NULL AND cash_flow <> 0
)
SELECT
    e.name                          AS series_name,
    ev.asset_id,
    ev.date::date                   AS date,
    ev.ev_rn,
    ROUND(ev.clean_before, 4)       AS clean_antes,
    ROUND(ev.clean_after, 4)        AS clean_depois,
    ROUND(ev.queda_pu, 4)           AS queda_pu,
    ROUND(ev.cash_flow, 4)          AS cash_flow,
    ROUND(ev.excesso, 4)            AS excesso,
    CASE
        WHEN ev.ev_rn = 1                              THEN 'compra'
        WHEN ev.excesso > (SELECT limiar_pu FROM params) THEN 'ERRO'
        ELSE 'ok'
    END                             AS flag
FROM ev
JOIN entities e ON e.id = ev.asset_id
WHERE ev.ev_rn > 1                                   -- exclui a compra (negativo legitimo)
  AND ev.excesso > (SELECT limiar_pu FROM params)    -- so os inconsistentes; comente p/ ver todos
ORDER BY ev.excesso DESC, e.name, ev.date;


-- ------------------------------------------------------------
-- ROLLUP por serie (opcional): quantos eventos do MEIO sao erro, por serie.
-- ------------------------------------------------------------
-- WITH params AS (SELECT 1.0::numeric AS limiar_pu),
-- base AS (
--     SELECT v.asset_id, v.date, v.id, v.cash_flow,
--            (v.clean_price + COALESCE(v.accrued_interest,0)) AS dirty_after,
--            LAG(v.clean_price + COALESCE(v.accrued_interest,0))
--                OVER (PARTITION BY v.asset_id ORDER BY v.date, v.id) AS dirty_before
--     FROM valuations v
--     WHERE v.asset_id IN (SELECT id FROM securitization_series)
-- ),
-- ev AS (
--     SELECT b.*,
--            ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY date, id) AS ev_rn,
--            ABS(cash_flow) - GREATEST(dirty_before - dirty_after, 0)    AS excesso
--     FROM base b WHERE cash_flow IS NOT NULL AND cash_flow <> 0
-- )
-- SELECT e.name, ev.asset_id,
--        COUNT(*) FILTER (WHERE ev_rn > 1)                                   AS n_meio,
--        COUNT(*) FILTER (WHERE ev_rn > 1 AND excesso > 1)                   AS n_erro,
--        ROUND(MAX(excesso) FILTER (WHERE ev_rn > 1), 4)                     AS max_excesso,
--        ROUND(SUM(excesso) FILTER (WHERE ev_rn > 1 AND excesso > 1), 2)     AS sum_excesso_erro
-- FROM ev JOIN entities e ON e.id = ev.asset_id
-- GROUP BY e.name, ev.asset_id
-- HAVING COUNT(*) FILTER (WHERE ev_rn > 1) > 0
-- ORDER BY n_erro DESC, max_excesso DESC NULLS LAST;
