-- ============================================================
-- util. Token -> securitization_series (e a mãe / CR)
-- ------------------------------------------------------------
-- Dado o nome de um token, retorna:
--   * securitization_series — a SÉRIE específica que o token representa.
--   * cr_mae                — a mãe (issuer do token, tk.issuer_id), a
--                             securitization CR-... que agrupa as séries.
--
-- A série específica NÃO sai de tk.issuer_id (isso é a mãe e, em estruturas
-- fracionadas, tem dezenas de séries). Ela vem da conta de colateral do token
-- ('assets pledged as collateral - <token>'), cuja posição (ISSUANCE) aponta
-- para a securitization_series correspondente.
--
-- securitization_series fica NULL p/ tokens de tokenização direta (TOKENIZATION
-- sobre o ativo, sem securitização) — nesses casos só a mãe é relevante.
-- ============================================================
SELECT
    token_e.name   AS token,
    s.series_name  AS securitization_series,
    s.series_id    AS securitization_series_id,
    mae_e.name     AS cr_mae,
    mae_e.id       AS cr_mae_id
FROM tokens tk
JOIN entities token_e  ON token_e.id = tk.id
JOIN entities mae_e    ON mae_e.id = tk.issuer_id
LEFT JOIN LATERAL (
    SELECT ss.id AS series_id, series_e.name AS series_name
    FROM financial_accounts fa
    JOIN positions pos             ON pos.financial_account_id = fa.id
    JOIN securitization_series ss  ON ss.id = pos.asset_id
    JOIN entities series_e         ON series_e.id = ss.id
    WHERE fa.name = 'assets pledged as collateral - ' || token_e.name
    GROUP BY ss.id, series_e.name
) s ON TRUE
WHERE token_e.name = ${ticker};
-- exemplos: 'NXCOL26-4' -> CR-CONSORTIUMS-26-01-SINGLE (mãe CR-CONSORTIUMS-26)
--           'NXFSC31-1' -> CR-FGTS-30-59-SENIOR        (mãe CR-FGTS-30)
