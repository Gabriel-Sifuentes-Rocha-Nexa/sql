-- ============================================================
-- util. Rentabilidade cadastrada das séries de um CR (a partir do nome da mãe)
-- ------------------------------------------------------------
-- Entrada (${ticker}): o nome do CR MÃE (a securitization), ex: 'CR-FGTS-30',
-- 'CR-CONSORTIUMS-26'. NÃO é o nome do token (use utils/token_to_cr_series.sql
-- para ir do token até a mãe).
--
-- Retorna uma linha por securitization_series do CR, com a rentabilidade
-- cadastrada na emissão:
--   indexer + indexer_percentage + spread_over_indexer.
-- Leitura: rendimento = (indexer_percentage % do indexer) + spread_over_indexer.
--   Ex.: indexer=CDI,  indexer_percentage=1.0, spread=0     -> "100% CDI"
--        indexer=IPCA, indexer_percentage=1.0, spread=0.06  -> "IPCA + 6%"
-- PREFIXADO (ex. FGTS): indexer_percentage=1.0 e a taxa fixa fica no spread
--   (ex. CR-FGTS-23-01-SINGLE: PREFIXADO, spread=0.16 -> 16% a.a.).
-- OBS: o `indexer_percentage = 0` do gotchas é da tabela `fgts` (parcela),
--   NÃO da securitization_series — aqui ele é 1.0.
-- ============================================================
SELECT
    mae_e.name              AS cr_mae,
    series_e.name           AS series_name,
    ss.series_number,
    sen.name                AS seniority,
    idx.name                AS indexer,
    ss.indexer_percentage,
    ss.spread_over_indexer,
    ss.issuance_date,
    ss.maturity_date
FROM entities mae_e
JOIN securitization_series ss   ON ss.issuer_id = mae_e.id
JOIN entities series_e          ON series_e.id = ss.id
JOIN indexers idx               ON idx.id = ss.indexer_id
JOIN seniorities sen            ON sen.id = ss.seniority_id
WHERE mae_e.name = 'CR-FGTS-23'
ORDER BY ss.series_number;
-- exemplo: 'CR-FGTS-30' (fracionado, ~60 séries) ; 'CR-CONSORTIUMS-26' (1 série SINGLE)
