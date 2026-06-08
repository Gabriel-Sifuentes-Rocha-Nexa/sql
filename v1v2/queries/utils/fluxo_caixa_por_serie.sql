-- ============================================================
-- UTIL. Fluxo de caixa pela CARACTERISTICA DA SERIE (nao pelo lastro)
-- ------------------------------------------------------------
-- Ideia (nova versao): em vez de somar os ativos de lastro (Q06-Q13),
-- pega-se o ULTIMO PU de cada serie e accrua-se ele com a "taxa que
-- falta" ate o vencimento. Modelo BULLET (1 resgate no vencimento).
--
--   PU sujo (hoje) = valuations.clean_price + valuations.accrued_interest
--                    na linha com last_valuation_flag = TRUE.
--   FV (resgate)   = PU_sujo * fator_de_accrual(pu_date -> maturity)
--   cash_flow      = FV * quantity  (no mes do vencimento)
--
-- FATOR DE ACCRUAL por indexador:
--   PREFIXADO : (1 + taxa)^(DU/252)             taxa = spread_over_indexer
--   CDI (pos) : (1 + ((1+r)^(1/252)-1)*pct)^DU  * (1 + spread)^(DU/252)
--               r = CDI a.a. projetado p/ o prazo (curva). pct = % do CDI.
--   USD       : (1 + taxa)^(dias360/360)  * FX  base 30/360, sem calendario  [STUB: falta FX]
--   IPCA+     : precisa projecao de inflacao (curves)                          [STUB]
--
-- DU 252: dias uteis no intervalo (pu_date, maturity], calendario `anbima`
--         ou `b3` (tabela holidays). Convencao do +1/endpoint documentada
--         no CTE `du` (ajuste de 1 linha se a sua bater diferente).
--
-- ESTADO LOCAL: a copia so tem series PREFIXADO e CDI. Por isso PREFIXADO
-- e CDI saem com status 'OK'; USD/IPCA saem 'STUB' (sem dado p/ validar).
-- A taxa CDI forward e' uma ASSUNCAO (params.forward_cdi_aa) ate confirmarmos
-- qual curve_id/vertice de `curves` e' o DI forward.
--
-- VALIDADO: entre eventos de caixa, o engine acretua o PU EXATAMENTE na taxa
-- contratual (var diaria = (1+taxa)^(1/252)-1, ex.: 0.000650/dia p/ 17.8%).
-- Logo o accrual (1+taxa)^(DU/252) reproduz a mecanica do proprio engine.
--
-- LIMITACAO (BULLET): este modelo so vale p/ series SEM amortizacao parcial.
-- Series amortizantes (FGTS: ~3.5%/mes de principal devolvido) tem o PU caindo
-- em degraus -> o "bullet" IGNORA as amortizacoes intermediarias e INFLA o
-- resgate final. O cronograma (securitization_payment_schedules) so esta
-- populado p/ as maes FIDC NXCO/NXFS, entao nao da p/ corrigir so com ele.
-- P/ o caso geral (amortizante, multi-indexador, timing de integralizacao),
-- a solucao robusta e' em Python (1 builder por TIPO de serie). Ver
-- fluxo_caixa_por_serie.py quando existir.
--
-- USO: roda pra TODAS as series por padrao. Para uma so, descomente o
--      filtro em `base` (WHERE e.name = ...).
-- ============================================================
WITH params AS (
    SELECT
        'anbima'::text  AS calendar,        -- calendario p/ DU 252 ('anbima' | 'b3')
        0.1500::numeric AS forward_cdi_aa   -- ASSUNCAO: CDI a.a. projetado (flat). Trocar por curva.
),
base AS (
    -- caracteristicas da serie + ultimo PU (sujo = clean + accrued)
    SELECT
        ss.id,
        e.name                                            AS series_name,
        idx.name                                          AS indexer,
        ss.indexer_percentage                             AS pct,      -- % do indexador (1 = 100%)
        ss.spread_over_indexer                            AS spread,   -- taxa (prefixado) / spread (pos)
        ss.maturity_date,
        ss.quantity,
        v.date::date                                      AS pu_date,
        (v.clean_price + COALESCE(v.accrued_interest, 0)) AS pu_dirty
    FROM securitization_series ss
    JOIN entities   e   ON e.id  = ss.id
    JOIN indexers   idx ON idx.id = ss.indexer_id
    JOIN valuations v   ON v.asset_id = ss.id
                       AND v.last_valuation_flag = TRUE
    -- WHERE e.name = 'CR-FGTS-12-01-SINGLE'   -- <- descomente p/ uma serie so
),
du AS (
    -- DU restantes no intervalo (pu_date, maturity]: conta dias uteis
    -- DEPOIS do pu_date (o PU ja inclui o accrual ate pu_date) ate o
    -- vencimento inclusive. Se sua convencao for [pu_date, maturity),
    -- troque (b.pu_date + 1, b.maturity_date) por (b.pu_date, b.maturity_date - 1).
    SELECT
        b.*,
        (
            SELECT count(*)
            FROM generate_series(b.pu_date + 1, b.maturity_date, INTERVAL '1 day') d
            WHERE EXTRACT(isodow FROM d) < 6                       -- seg-sex
              AND d::date NOT IN (
                    SELECT h.date FROM holidays h
                    WHERE h.calendar = (SELECT calendar FROM params)
              )
        ) AS du_252,
        -- dias 30/360 (US/NASD) p/ USD: aritmetica pura de data, sem calendario
        (
            (EXTRACT(year  FROM b.maturity_date) - EXTRACT(year  FROM b.pu_date)) * 360
          + (EXTRACT(month FROM b.maturity_date) - EXTRACT(month FROM b.pu_date)) * 30
          + (LEAST(EXTRACT(day FROM b.maturity_date), 30) - LEAST(EXTRACT(day FROM b.pu_date), 30))
        ) AS days_360
    FROM base b
),
accrued AS (
    SELECT
        d.*,
        CASE d.indexer
            WHEN 'PREFIXADO' THEN
                power(1 + d.spread, d.du_252::numeric / 252)
            WHEN 'CDI' THEN
                -- componente CDI (% do CDI, capitalizado dia a dia) * componente spread
                  power(1 + (power(1 + (SELECT forward_cdi_aa FROM params), 1.0 / 252) - 1) * d.pct,
                        d.du_252)
                * power(1 + d.spread, d.du_252::numeric / 252)
            -- WHEN 'DOLLAR_PTAX' THEN power(1 + d.spread, d.days_360::numeric / 360)  -- * FX (exchange_rates)  [STUB]
            -- WHEN 'SOFR'        THEN power(1 + d.spread, d.days_360::numeric / 360)  -- * FX                   [STUB]
            -- WHEN 'IPCA'        THEN ...projecao de inflacao via curves...           [STUB]
            ELSE NULL
        END AS accrual_factor
    FROM du d
)
SELECT
    series_name,
    indexer,
    pu_date,
    round(pu_dirty, 8)                                  AS pu_dirty,
    maturity_date,
    du_252,
    round(accrual_factor, 8)                            AS accrual_factor,
    round(pu_dirty * accrual_factor, 8)                 AS redemption_pu,
    quantity,
    round(pu_dirty * accrual_factor * quantity, 2)      AS cash_flow_total,
    TO_CHAR(maturity_date, 'YYYY-MM')                   AS month_year_maturity,
    CASE
        WHEN indexer IN ('DOLLAR_PTAX', 'SOFR') THEN 'USD'
        ELSE 'BRL'
    END                                                 AS currency,
    CASE
        WHEN indexer IN ('PREFIXADO', 'CDI') THEN 'OK'
        ELSE 'STUB (falta curva/FX)'
    END                                                 AS status
FROM accrued
ORDER BY month_year_maturity, series_name;


-- ------------------------------------------------------------
-- SANIDADE (opcional): para PREFIXADO, accruar o initial_price desde a
-- emissao ate o pu_date deve reproduzir o PU sujo atual. Se bater, o
-- DU/252 e a taxa estao consistentes com a precificacao do engine.
-- ------------------------------------------------------------
-- SELECT e.name,
--        ss.initial_price,
--        v.clean_price + COALESCE(v.accrued_interest,0) AS pu_dirty_hoje,
--        ss.initial_price * power(1 + ss.spread_over_indexer,
--            (SELECT count(*) FROM generate_series(ss.issuance_date + 1, v.date::date, INTERVAL '1 day') d
--             WHERE EXTRACT(isodow FROM d) < 6
--               AND d::date NOT IN (SELECT date FROM holidays WHERE calendar='anbima'))::numeric / 252
--        ) AS pu_recalculado
-- FROM securitization_series ss
-- JOIN entities e   ON e.id = ss.id
-- JOIN indexers idx ON idx.id = ss.indexer_id AND idx.name = 'PREFIXADO'
-- JOIN valuations v ON v.asset_id = ss.id AND v.last_valuation_flag = TRUE
-- ORDER BY e.name;
