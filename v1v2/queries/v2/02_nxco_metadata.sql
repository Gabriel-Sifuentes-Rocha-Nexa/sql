-- ============================================================
-- 2. NXCO — Obter metadados do Asset
-- ------------------------------------------------------------
-- V1 ORIGINAL (Supabase, securities + metadata JSONB):
-- ------------------------------------------------------------
-- SELECT
--     s2.name,
--     s2.full_name,
--     s2.code,
--     s2.metadata,
--     s2.type,
--     (s2.metadata->'linhas'->0->'administradora'->'nome') as adm_name,
--     (s2.metadata->'linhas'->0->'administradora'->'documento') as adm_cnpj,
--     (s2.metadata->'linhas'->0->'recebivel'->'cota_numero') as quota_number,
--     (s2.metadata->'linhas'->0->'recebivel'->'grupo_numero') as group_number,
--     (s2.metadata->'linhas'->0->'recebivel'->'indice_reajuste') as index_name,
--     (s2.metadata->'linhas'->0->'recebivel'->'valor_compra') as total_value,
--     (s2.metadata->'internal'->'strategy') as strategy
-- FROM securities s1
-- CROSS JOIN LATERAL jsonb_array_elements(s1.metadata->'composition') as compositions
-- JOIN securities s2 ON s2.aux_id = (compositions->>'asset_aux_id')::uuid
-- WHERE s1.code = ${ticker}
-- ------------------------------------------------------------
-- ============================================================
SELECT
    -- Identificação
    quota_entity.name                       AS quota_name,                 -- s2.name (V1)
    c.code,                                                                -- s2.code (V1)
    'cota de consorcio - ' || cs.name       AS type,                       -- s2.type (V1)
    -- Classificação
    cs.name                                 AS strategy_name,              -- internal.strategy (V1)
    cua.name                                AS underlying_asset_name,
    st.name                                 AS status_name,
    c.checked,
    c.wallet_fidc,
    -- Contrato / cota
    c.contract_number,
    c.quota_number,
    c.quota_group_number                    AS group_number,               -- (V1: group_number)
    -- Counterparties
    assignee_entity.name                    AS assignee_name,
    originator_entity.name                  AS originator_name,
    trustee_entity.name                     AS trustee_name,               -- (V1: adm_name)
    trustee_ci.document                     AS trustee_cnpj,               -- (V1: adm_cnpj)
    c.assignor,
    -- Datas
    c.acquisition_date,
    c.group_end_date,
    c.expected_contemplation_date,
    c.contemplation_date,
    c.expected_maturity_date,
    c.maturity_date_original,
    c.maturity_date,
    c.discharge_date,
    -- Valores financeiros
    c.acquisition_price                     AS total_value,                -- (V1: total_value)
    c.credit_value,
    c.quota_outstanding_balance,
    c.face_value_original,
    c.face_value,
    c.embedded_bid_value,
    c.contemplation_value,
    c.presentvalue_outstanding_balance,
    c.updated_outstanding_balance,
    c.commission_value,
    c.transfer_fee_value,
    c.commissions_payable,
    c.transfer_fees_payable,
    -- Indexador / taxas
    idx.name                                AS index_name,                 -- (V1: index_name)
    c.cdi_debtor,
    c.implied_inflation_ann,
    c.spread_over_cdi,
    c.yearly_return,
    c.assignment_fra,
    c.yield_correction,
    c.transferred_to_fund,
    -- Dados bancários
    c.bank,
    c.agency,
    c.agency_digit,
    c.account,
    c.account_digit,
    c.account_type
FROM consortiums c
JOIN entities quota_entity                      ON quota_entity.id = c.id
JOIN entities assignee_entity                   ON assignee_entity.id = c.assignee_id
JOIN entities originator_entity                 ON originator_entity.id = c.originator_id
JOIN entities trustee_entity                    ON trustee_entity.id = c.trustee_id
LEFT JOIN contact_infos trustee_ci              ON trustee_ci.id = trustee_entity.id
JOIN consortium_strategies cs                   ON cs.id = c.strategy_id
JOIN consortium_underlying_assets cua           ON cua.id = c.underlying_asset_id
JOIN statuses st                                ON st.id = c.status_id
JOIN indexers idx                               ON idx.id = c.indexer_id
JOIN positions pos                              ON pos.asset_id = c.id
JOIN transaction_types tt                       ON tt.id = pos.transaction_type_id
                                                AND tt.name = 'TOKENIZATION'
JOIN financial_accounts token_fa                ON token_fa.id = pos.financial_account_id
JOIN entities token_entity                      ON token_fa.name = 'assets pledged as collateral - ' || token_entity.name
-- WHERE token_entity.name = ${ticker};
WHERE token_entity.name = 'NXCOC26-1';  -- exemplo para testes
