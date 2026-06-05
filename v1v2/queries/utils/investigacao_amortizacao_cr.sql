-- ============================================================
-- Posições (V2 / engine) da série CR-FGTS-30-01-SENIOR e do token
-- par a ela (NXFSE26-1) — TODAS as linhas, com nomes legíveis
-- (ativo, holder, financial account, transaction type).
-- Para trocar de ativo, edite os nomes no WHERE.
-- ============================================================
SELECT
       p.date                        AS data_hora,
       a.name                        AS ativo,
       h.name                        AS holder,
       fa.name                       AS financial_account,
       tt.name                       AS transaction_type,
       p.lot_id,
       p.variation,
       p.total_quantity,
       p.last_position_flag,
       p.block_id
FROM positions p
JOIN entities a                 ON a.id = p.asset_id
JOIN entities h                 ON h.id = p.holder_id
LEFT JOIN financial_accounts fa ON fa.id = p.financial_account_id
LEFT JOIN transaction_types tt  ON tt.id = p.transaction_type_id
WHERE a.name IN ('CR-FGTS-30-01-SENIOR', 'NXFSE26-1')
ORDER BY a.name, p.date, p.id;


-- ============================================================
-- Mesma visão, mas para TODAS as posições carregadas pelo holder
-- NXTPL28-1 (qualquer ativo). Para trocar de holder, edite o WHERE.
-- ============================================================
SELECT
       p.date                        AS data_hora,
       a.name                        AS ativo,
       h.name                        AS holder,
       fa.name                       AS financial_account,
       tt.name                       AS transaction_type,
       p.lot_id,
       p.variation,
       p.total_quantity,
       p.last_position_flag,
       p.block_id
FROM positions p
JOIN entities a                 ON a.id = p.asset_id
JOIN entities h                 ON h.id = p.holder_id
LEFT JOIN financial_accounts fa ON fa.id = p.financial_account_id
LEFT JOIN transaction_types tt  ON tt.id = p.transaction_type_id
WHERE h.name = 'NXTPL28-1'
ORDER BY a.name, p.date, p.id;


select * from valuations where asset_id in (select id from entities where name='CR-FGTS-30-01-SENIOR')
order by date desc;


-- ============================================================
-- Tokens INTEGRALIZADOS da série — conta 'integralized tokens'.
-- ${ticker} = nome da SÉRIE (ex.: CR-FGTS-30-01-SENIOR); deriva o token via colateral.
--   integralizado_total   = total já integralizado (SUM das INTEGRALIZATION na conta)
--   integralizado_vigente = saldo atual na conta (last_position_flag = true) — 0 se já resgatado
-- ============================================================
WITH tok AS (   -- token cujo colateral aponta para a série
    SELECT DISTINCT token_e.id AS token_id, token_e.name AS token_name
    FROM securitization_series ss
    JOIN entities series_e         ON series_e.id = ss.id
    JOIN positions pos             ON pos.asset_id = ss.id
    JOIN financial_accounts fa_col ON fa_col.id = pos.financial_account_id
                                  AND fa_col.name LIKE 'assets pledged as collateral - %'
    JOIN entities token_e          ON token_e.name = replace(fa_col.name, 'assets pledged as collateral - ', '')
    JOIN tokens tk                 ON tk.id = token_e.id
    WHERE series_e.name = ${ticker}
)
SELECT t.token_name AS token,
       SUM(p.variation)      FILTER (WHERE tt.name = 'INTEGRALIZATION') AS integralizado_total,
       SUM(p.total_quantity) FILTER (WHERE p.last_position_flag)        AS integralizado_vigente
FROM tok t
JOIN positions p           ON p.asset_id = t.token_id
JOIN financial_accounts fa ON fa.id = p.financial_account_id AND fa.name = 'integralized tokens'
JOIN transaction_types tt  ON tt.id = p.transaction_type_id
GROUP BY t.token_name;