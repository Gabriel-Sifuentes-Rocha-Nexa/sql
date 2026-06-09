-- ============================================================
-- View: valuation_with_durations
-- Banco ALVO: V2 local (engine @ 127.0.0.1:5432, PG nativo). View NAO materializada.
-- ------------------------------------------------------------
-- STATUS (2026-06-09): NAO EM USO / PARADA. Mantida como ponto de partida.
--   O dono decidiu nao usar por ora. Motivo: "duration" de verdade e bem mais
--   complexa do que (vencimento - data)/360. Esse calculo simples so equivale a
--   duration para ativos BULLET (1 pagamento unico no vencimento). Varios tokens
--   -- em especial consorcio (NXCO) -- NAO sao bullet: amortizam / tem multiplos
--   fluxos, entao "anos ate o vencimento final" NAO e a duration real deles.
--   Uma duration correta precisa ser ponderada pelo fluxo de caixa (Macaulay /
--   modified) e so faz sentido se existir de forma CONSISTENTE para TODOS os
--   ativos -- nao so para esses ~76 tokens. Ate la, ler duration_years aqui como
--   "tempo ate o vencimento final" (proxy), NAO como duration financeira.
-- ------------------------------------------------------------
-- O que e:
--   Todas as linhas de `valuations` cujo ATIVO e um TOKEN que (a) e "de CR"
--   e (b) tem nome (entities.name) comecando com NXNI, NXCO ou NXFS. Traz
--   TODAS as colunas de `valuations` -- exceto a duration_years original --
--   e, no final, uma coluna `duration_years` recalculada como os anos que
--   faltam pro token vencer.
--
-- /!\ SEMANTICA DA COLUNA duration_years NESTA VIEW (decisao do dono):
--   A tabela `valuations` JA tem `duration_years` (numeric(8,4)) = duration do
--   FLUXO DE CAIXA. Aqui ela e SUBSTITUIDA: o `duration_years` desta view e
--   "anos ate o vencimento" -- NAO a duration do fluxo de caixa. E o unico
--   duration_years da view, posicionado no fim.
--
-- Calculo (dias corridos / 360), POR LINHA, relativo a DATA DA VALUATION (v.date):
--   duration_years = ROUND( (tokens.maturity_date - valuations.date::date) / 360.0 , 4)
--   * dias CORRIDOS entre a data DAQUELA valuation e o vencimento final do token,
--     / 360 (base), 4 casas.
--   * USA v.date, NAO CURRENT_DATE: com CURRENT_DATE todas as linhas do mesmo token
--     sairiam IGUAIS. Com v.date a duration DIMINUI ao longo das datas (quanto mais
--     recente a valuation, menos tempo falta pro vencimento).
--   * maturity NULL -> NULL ; valuation com data APOS o vencimento -> NEGATIVO (sem clamp).
--
-- Filtro "so tokens de CR" (via structure_id, conforme pedido):
--   "de CR" = token cuja structure e securitizacao em tranche, i.e.
--   token_structures.structure_name IN ('single tranche','multiple tranches').
--   structure_id resolvido por nome no subselect (robusto a reordenacao de ids).
--   token_structures no banco (validado 2026-06-08): 1=single tranche (30 tok,
--   100% CR), 2=multiple tranches (63, 100% CR), 3=assets (233; MISTA: 215 CR +
--   18 tokenizacao direta), 5=portfolio (4, 100% CR). Por decisao, "de CR" = 1 e 2
--   (exclui 'assets' e 'portfolio').
--
-- Filtro de prefixo (literal): entities.name LIKE 'NXNI%'/'NXCO%'/'NXFS%'.
--   /!\ NAO inclui 'NXFGTS%' -> 17 tokens FGTS de CR (single/multiple tranche)
--       nomeados NXFGTS... ficam DE FORA. Com o filtro atual a view rende ~76
--       tokens. Para incluir esses 17, acrescente `OR e.name LIKE 'NXFG%'` abaixo.
--
-- Ligacoes (gotcha #5: tokens.id = entities.id = valuations.asset_id):
--   valuations.asset_id -> tokens.id -> entities.id. O JOIN em `tokens` ja
--   restringe aos ativos que sao token. Vencimento final = tokens.maturity_date.
--
-- Escopo das linhas: TODAS as valuations de cada token (todas as datas,
--   metodologias e lots) -- NAO filtra last_valuation_flag. Para so a ultima de
--   cada (asset, lot, methodology), acrescente `AND v.last_valuation_flag`.
-- ============================================================


-- ------------------------------------------------------------
-- Verificacao opcional (read-only): structures e o split CR vs direto.
--   Resultado 2026-06-08: single tranche 30/30 CR | multiple tranches 63/63 CR
--   | assets 215 CR + 18 direto | portfolio 4/4 CR.
-- ------------------------------------------------------------
-- SELECT ts.id AS structure_id, ts.structure_name, COUNT(*) AS tokens,
--        COUNT(*) FILTER (WHERE sec.id IS NOT NULL) AS cr_securitizados,
--        COUNT(*) FILTER (WHERE sec.id IS NULL)     AS nao_cr_direto
-- FROM tokens tk
-- JOIN token_structures ts      ON ts.id  = tk.structure_id
-- LEFT JOIN securitizations sec ON sec.id = tk.issuer_id
-- GROUP BY ts.id, ts.structure_name ORDER BY ts.id;


-- ------------------------------------------------------------
-- A VIEW
-- ------------------------------------------------------------
-- DROP VIEW IF EXISTS valuation_with_durations;   -- use se precisar recriar com colunas diferentes

CREATE OR REPLACE VIEW valuation_with_durations AS
SELECT
    v.id,
    v.date,
    v.asset_id,
    v.lot_id,
    v.methodology_id,
    v.clean_price,
    v.accrued_interest,
    v.indexer_id,
    v.indexer_percentage,
    v.spread_over_indexer,
    v.spread_over_cdi,
    v.spread_over_inflation,
    v.cash_flow,
    v.currency_id,
    v.last_valuation_flag,
    v.created_at,
    v.updated_at,
    -- duration_years SUBSTITUIDO: anos corridos da DATA DA VALUATION (v.date) ate o
    -- vencimento do token / 360. Usa v.date (NAO CURRENT_DATE) -> varia por linha,
    -- diminuindo rumo ao vencimento.
    ROUND((tk.maturity_date - v.date::date)::numeric / 360.0, 4) AS duration_years
FROM valuations v
JOIN tokens   tk ON tk.id = v.asset_id
JOIN entities e  ON e.id  = tk.id
WHERE tk.structure_id IN (
          SELECT id FROM token_structures
          WHERE structure_name IN ('single tranche', 'multiple tranches')   -- = "de CR"
      )
  AND ( e.name LIKE 'NXNI%'
     OR e.name LIKE 'NXCO%'
     OR e.name LIKE 'NXFS%' );    -- + 'OR e.name LIKE ''NXFG%''' p/ incluir os 17 NXFGTS de CR


/* ============================================================
   DBML (Postgres) — a MESMA view para diagrama (dbdiagram.io / dbml.org).
   DBML nao tem tipo nativo de VIEW: modelada como Table + Note. A logica do
   SELECT (filtros, JOINs, o calculo de duration_years) NAO e expressavel em
   DBML -- fica descrita no Note. Tipos espelham a tabela `valuations`.
   Cole no schemas/db_diagram_v2.txt p/ os Refs resolverem (entities/etc.).
   ------------------------------------------------------------
Table public.valuation_with_durations [headercolor: #1E69FD] {
  id bigint
  date timestamptz
  asset_id bigint [note: 'token: = entities.id (so tokens de CR + prefixo NXNI/NXCO/NXFS)']
  lot_id integer
  methodology_id integer
  clean_price decimal(20,8)
  accrued_interest decimal(20,8)
  indexer_id smallint
  indexer_percentage decimal(12,8)
  spread_over_indexer decimal(12,8)
  spread_over_cdi decimal(12,8)
  spread_over_inflation decimal(12,8)
  cash_flow decimal(20,8)
  currency_id integer
  last_valuation_flag bool
  created_at timestamptz
  updated_at timestamptz
  duration_years numeric [note: 'SUBSTITUI a original: anos da data da valuation (date) ate o vencimento = ROUND((tokens.maturity_date - valuations.date::date)/360, 4); varia por linha, diminui no tempo']

  Note: '''
  VIEW NAO materializada (CREATE OR REPLACE VIEW).
  Linhas = todas as valuations de tokens "de CR"
  (token_structures.structure_name IN (single tranche, multiple tranches))
  cujo entities.name comeca com NXNI / NXCO / NXFS.
  duration_years aqui = anos corridos da data de CADA valuation (v.date) ate o
  vencimento do token (dias / 360, 4 casas) -- diminui conforme a data avanca;
  NAO e a duration do fluxo de caixa da tabela valuations.
  '''
}

Ref: public.valuation_with_durations.asset_id       > public.entities.id
Ref: public.valuation_with_durations.currency_id    > public.currencies.id
Ref: public.valuation_with_durations.methodology_id > public.valuation_methodologies.id
Ref: public.valuation_with_durations.indexer_id     > public.indexers.id
   ============================================================ */
