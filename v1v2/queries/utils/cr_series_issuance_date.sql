-- ============================================================
-- util. Data de emissão de uma CR series
-- ------------------------------------------------------------
-- Entrada (${ticker}): o nome da CR SERIES (securitization_series), ex:
-- 'CR-FGTS-30-59-SENIOR', 'CR-CONSORTIUMS-26-01-SINGLE'.
-- (Para chegar à série a partir de um token, use utils/token_to_cr_series.sql.)
--
-- Retorna a data de emissão cadastrada da série (securitization_series.issuance_date),
-- com a mãe e o vencimento para contexto.
-- ============================================================
SELECT
    series_e.name       AS cr_series,
    mae_e.name          AS cr_mae,
    ss.issuance_date,
    ss.maturity_date
FROM securitization_series ss
JOIN entities series_e  ON series_e.id = ss.id
JOIN entities mae_e     ON mae_e.id = ss.issuer_id
WHERE series_e.name like 'CR-FGTS-32%';
-- exemplo: 'CR-FGTS-30-59-SENIOR' ; 'CR-CONSORTIUMS-26-01-SINGLE'
