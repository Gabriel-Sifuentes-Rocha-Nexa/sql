-- ============================================================
-- util. Auditoria do NOME do token FGTS no Engine V2
-- ------------------------------------------------------------
-- Banco ALVO: V2 (engine, AWS/local — tabelas tipadas)
--
-- Para a lista fixa de tokens FGTS abaixo, resolve:
--   * serie_v2     — a securitization_series que o token representa
--                    (via conta de colateral, padrao validado em
--                     token_to_cr_series.sql).
--   * mae_cr       — a securitization mae (tk.issuer_id) = o "CR-FGTS-N".
--   * os campos que o NOME do token parece codificar, para auditar se
--     o nome bate com a serie subjacente:
--       - seniority / tag         (o "JR" do nome = subordinated?)
--       - serie_maturity_date     (o "<letra><AA>" = mes/ano de vencimento?)
--       - series_number / count   (o sufixo "-N"?)
--
-- Decodificacao HIPOTETICA do nome V2 (a confirmar com as colunas abaixo):
--   NX FGTS [JR] [letra=mes A..L] [AA=ano] - [sufixo]
--   ex.: NXFGTSL40-... -> L=12 (Dez), 40=2040 ; JR = subordinada.
--
-- Use os nomes EXATOS de mae_cr que isto retornar como input do
-- companion fgts_token_name_audit_v1.sql (a mae e' identica em V1 e V2).
-- ============================================================
WITH alvo(input_cr, token_name) AS (
    VALUES
        ('CR-FGTS-01',              'NXFGTSL34-1'),
        ('CR-FGTS-04',              'NXFGTSI35-4'),
        ('CR-FGTS-05',              'NXFGTSI35-5'),
        ('CR-FGTS-06',              'NXFGTSI35-6'),
        ('CR-FGTS-08 SUBORDINATED', 'NXFGTSJRL40-8.3')   -- caso especial (subordinada)
)
SELECT
    a.input_cr,
    a.token_name,
    tok_e.id                       AS token_id,
    mae_e.name                     AS mae_cr,
    mae_e.id                       AS mae_cr_id,
    ser_e.name                     AS serie_v2,
    ser.id                         AS serie_v2_id,
    ser.series_number,
    sen.name                       AS seniority,
    sen.tag                        AS seniority_tag,
    ser.seniority_number,
    ser.issuance_number,
    ser.issuance_date              AS serie_issuance_date,
    ser.maturity_date              AS serie_maturity_date,
    idx.name                       AS serie_indexer,
    ser.indexer_percentage,
    ser.spread_over_indexer,
    -- atributos do proprio TOKEN (candidatos a fonte do nome)
    tk.maturity_date               AS token_maturity_date,
    tk.issuance_count              AS token_issuance_count,
    tk.issuer_code                 AS token_issuer_code
FROM alvo a
LEFT JOIN entities tok_e ON tok_e.name = a.token_name
LEFT JOIN tokens   tk    ON tk.id = tok_e.id
LEFT JOIN entities mae_e ON mae_e.id = tk.issuer_id
LEFT JOIN LATERAL (
    SELECT DISTINCT
           ss.id, ss.series_number, ss.seniority_id, ss.seniority_number,
           ss.issuance_number, ss.issuance_date, ss.maturity_date,
           ss.indexer_id, ss.indexer_percentage, ss.spread_over_indexer
    FROM financial_accounts fa
    JOIN positions pos            ON pos.financial_account_id = fa.id
    JOIN securitization_series ss ON ss.id = pos.asset_id
    WHERE fa.name = 'assets pledged as collateral - ' || tok_e.name
) ser ON TRUE
LEFT JOIN entities    ser_e ON ser_e.id = ser.id
LEFT JOIN seniorities sen   ON sen.id = ser.seniority_id
LEFT JOIN indexers    idx   ON idx.id = ser.indexer_id
ORDER BY a.input_cr, ser.series_number;
-- RESULTADO (rodado 2026-06-08 no engine local 5432/engine):
--   CR-01 -> CR-FGTS-01-01-SINGLE        (venc 2034-12-23) -> NXFGTSL34-1
--   CR-04 -> CR-FGTS-04-01-SINGLE        (venc 2035-09-15) -> NXFGTSI35-4
--   CR-05 -> CR-FGTS-05-01-SINGLE        (venc 2035-09-15) -> NXFGTSI35-5
--   CR-06 -> CR-FGTS-06-01-SINGLE        (venc 2035-09-15) -> NXFGTSI35-6
--   CR-08 -> CR-FGTS-08-03-SUBORDINATED  (venc 2040-12-15) -> NXFGTSJRL40-8.3
--   (familia CR-08: 01-SENIOR->NXFGTSSRL31-8.1, 02-MEZZANINE->NXFGTSMZL31-8.2, 03-SUBORDINATED->NXFGTSJRL40-8.3)
-- Regra do ticker: NX FGTS [SR|MZ|JR se tranche] <letra=mes venc A=Jan..L=Dez> <AA ano> - <issuance_number>[.series_number]
-- token_maturity_date == serie_maturity_date em todos (sem divergencia interna no V2).
