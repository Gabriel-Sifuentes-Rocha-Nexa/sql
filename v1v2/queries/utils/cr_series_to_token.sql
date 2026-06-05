-- ============================================================
-- util. securitization_series (CR-série) -> Token  (inverso de token_to_cr_series)
-- ------------------------------------------------------------
-- Dado o nome de uma securitization_series, retorna:
--   * token   — o token que REPRESENTA essa série (colateraliza-a).
--   * cr_mae  — a mãe (tk.issuer_id), a securitization CR-... que agrupa as séries.
--
-- O vínculo é o mesmo de token_to_cr_series, só que percorrido ao contrário:
-- a série aparece como ativo (pos.asset_id) numa posição cuja financial_account é
-- a conta de colateral de um token ('assets pledged as collateral - <token>').
-- Extraímos o nome do token do nome dessa conta e confirmamos em `tokens`.
--
-- token fica vazio se a série não for colateral de nenhum token (ex.: série sem
-- token emitido ainda). Em fracionados, cada série tende a 1 token.
-- ${ticker} aqui = NOME DA SÉRIE (não do token).
-- ============================================================
SELECT
    series_e.name  AS securitization_series,
    series_e.id    AS securitization_series_id,
    token_e.name   AS token,
    token_e.id     AS token_id,
    mae_e.name     AS cr_mae,
    mae_e.id       AS cr_mae_id
FROM securitization_series ss
JOIN entities series_e          ON series_e.id = ss.id
JOIN positions pos              ON pos.asset_id = ss.id
JOIN financial_accounts fa      ON fa.id = pos.financial_account_id
                               AND fa.name LIKE 'assets pledged as collateral - %'
JOIN entities token_e           ON token_e.name = replace(fa.name, 'assets pledged as collateral - ', '')
JOIN tokens tk                  ON tk.id = token_e.id
JOIN entities mae_e             ON mae_e.id = tk.issuer_id
WHERE series_e.name = ${ticker}
GROUP BY series_e.name, series_e.id, token_e.name, token_e.id, mae_e.name, mae_e.id
ORDER BY token_e.name;
-- exemplos (inverso dos de token_to_cr_series):
--   'CR-FGTS-30-01-SENIOR'        -> NXFSE26-1  (mãe CR-FGTS-30)
--   'CR-FGTS-30-59-SENIOR'        -> NXFSC31-1  (mãe CR-FGTS-30)
--   'CR-CONSORTIUMS-26-01-SINGLE' -> NXCOL26-4  (mãe CR-CONSORTIUMS-26)
