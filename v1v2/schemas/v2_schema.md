---
name: Reference — Engine V2 (AWS PostgreSQL) Schema
description: Authoritative V2 schema — full table list, quirks, trigger-maintained fields, valuation methodologies
type: reference
tags: [tipo/referência, conceito/migração, team/engine]
resumo: "DDL V2 (AWS PostgreSQL): tabelas, quirks críticos (triggers, FKs incomuns), metodologias de valuação"
originSessionId: 1a871832-5698-4353-8002-148d6e94407d
schema_as_of: 2026-05-12
---
## Convenções (aplicam-se a todas as tabelas, salvo nota explícita)

- Toda tabela tem `created_at timestamptz NOT NULL DEFAULT now()` e `updated_at timestamptz` (nullable).
- `id` é PK auto-incremento (serial/bigserial/smallserial conforme tipo). Quando `id` aparece como FK para `entities` (tabelas de ativos), o id da tabela é o mesmo do entity.
- Tabelas de lookup seguem `id smallserial pk, name varchar(50) unique` — só listo colunas adicionais ou desvios.
- `→tabela` denota FK; `(nullable)` quando aplicável; ausência = NOT NULL.
- Tabelas de ativos usam `entities.id` como PK (FK `id→entities`).
- Schema owner: `engine_team`; database `public`.

### Enums
- `consortium_checked_enum` (not_checked|directly|sampling)
- `consortium_types_enum` (contemplada|contemplacao|cancelada)
- `document_types_enum` (cpf|cnpj)
- `fidc_wallets_enum` ("1"|"2"|"3")
- `financial_account_classifications_enum` (debit|credit)
- `holidays_calendar_enum` (anbima|b3)
- `log_statuses_enum` (success|failed)
- `operations_enum` (delete|update)

---

## Quirks críticos

- `total_quantity` em `positions` é **soma cumulativa mantida por trigger** de `variation` (ordenada por date ASC, id ASC, particionada por holder/asset/lot/financial_account). **Não escrever diretamente.**
- `last_position_flag` (positions) e `last_valuation_flag` (valuations) são **mantidos por trigger** (AFTER INSERT/UPDATE/DELETE). **Não escrever diretamente.**
- `expected_cash_flows.currency_id` FK aponta para `entities.id` (não para `currencies.id`) — quirk conhecido.
- **`securitization_series` não tem `currency_id`**. Currency só vive em `valuations.currency_id` e `expected_cash_flows.currency_id`. Payload de criação aceita `series_currency` (ex: `"USD"` para NTN-I); API resolve para currency id ao criar a primeira valuation. Runs diárias propagam currency das valuations anteriores.
- **Metodologias de valuação em uso**: `amortized_cost` (padrão, todos asset classes); `amortized_cost_original` (consórcio — custo amortizado pelo valor original de aquisição); `face_value`, `zero_spread` (operacionais de consórcio).

---

## Tabelas

### Operacional / auditoria
- `alembic_version` — version_num varchar(32) pk (sem created_at/updated_at)
- `histories` — id bigserial, created_by varchar(50), table_name varchar(50), old_value jsonb, operation operations_enum, description varchar(200) (sem updated_at)
- `logs` — id bigserial, protocol varchar(100), begin_date, end_date, duration_seconds int, status log_statuses_enum, message text (sem updated_at)
- `fgts_redemption_processed_paths` — path varchar(200) unique

### Lookup (todos seguem `id smallserial pk, name varchar(50) unique` salvo nota)
- `holidays` — date, description varchar(100), calendar holidays_calendar_enum; unique(date, description, calendar)
- `sources` — name varchar(100) unique
- `reference_tables` — (mapeia entity type → nome da tabela de asset)
- `statuses`
- `indexers`
- `valuation_methodologies` — id integer pk
- `transaction_types`
- `parameter_types`
- `seniorities` — +tag char(3)
- `offers` — name varchar(30) unique
- `registers` — name varchar(30) unique
- `frequencies` — name varchar(30) unique (**plural**, não "frequency")
- `securitization_expense_names` — name varchar(30) unique
- `securitization_expense_types` — name varchar(30) unique
- `consortium_strategies`
- `consortium_underlying_assets`
- `securitization_underlying_assets`
- `token_strategies` — strategy_code varchar(30), strategy_name varchar(100), strategy_asset varchar(100); unique(strategy_code, strategy_name)
- `token_structures` — structure_name varchar(100)
- `risk_types` — +parent_id int (self-FK)
- `entity_types_ref` — +parent_id smallint (self-FK)
- `financial_accounts` — id integer, name varchar(200) unique, classification financial_account_classifications_enum, parent_id smallint (self-FK); unique(name, classification)

### Currency / FX
- `currency_issuers` — name varchar(50) unique
- `currencies` — id integer pk, currency_issuer_id smallint unique→currency_issuers (sem `name`; nome vem do issuer)
- `exchange_rates` — id int, numerator_id→currencies, denominator_id→currencies, methodology_id→valuation_methodologies, date timestamptz, value decimal(18,6), source_id→sources; unique(numerator_id, denominator_id, date, methodology_id)

### Entidades
- `entities` — id serial pk, name varchar(100) unique, source_id→sources, reference_table_id→reference_tables, doc_id bigint
- `entity_types` — id int, entity_id→entities, ref_id→entity_types_ref; unique(entity_id, ref_id)
- `contact_infos` — id→entities (PK==FK), document varchar(14), document_type document_types_enum, email, phone, wallet, zip, address, number, complement, neighborhood, city, state, country, website
- `bank_accounts` — id int, entity_id→entities, name varchar(50), description varchar(200), bank varchar(3), agency, account, account_digit, account_type, agency_digit; unique(entity_id, name)

### Tabelas de ativos (id→entities)
- `consortiums` — code varchar(100) unique, assignee_id→entities, originator_id→entities, strategy_id→consortium_strategies, underlying_asset_id→consortium_underlying_assets, cdi_debtor numeric(8,4), quota_number, acquisition_date, group_end_date, quota_group_number, acquisition_price, credit_value, quota_outstanding_balance, commission_value, contemplation_value, face_value_original, face_value, contract_number, expected_maturity_date, maturity_date_original, maturity_date, indexer_id→indexers, transferred_to_fund bool, embedded_bid_value, presentvalue_outstanding_balance, updated_outstanding_balance, transfer_fee_value, trustee_id→entities, status_id→statuses, checked consortium_checked_enum (nullable), implied_inflation_ann numeric(8,6), spread_over_cdi numeric(8,6), assignment_fra numeric(8,6), yield_correction numeric(8,6), expected_contemplation_date, contemplation_date (nullable), discharge_date (nullable), wallet_fidc fidc_wallets_enum (nullable), commissions_payable, transfer_fees_payable, assignor varchar(100), bank varchar(3), agency, account, account_digit, account_type, agency_digit
- `fgts` — cession_id int, status_id→statuses, assignment_date, originator_id→entities, contract varchar(50), cef_uuid uuid (nullable), cef_protocol (nullable), obligor_bank (nullable), obligor_bank_code char(3) (nullable), assignor_id→entities (nullable), assignee_id→entities (nullable), obligor_person_type char(1) (nullable), obligor_gender, obligor_uf char(2), obligor_city, obligor_neighbourhood, obligor_street, obligor_zip_code char(8), obligor_birthday_date, contract_emission_date, contract_disbursement_value, contract_original_debt_value, acquisition_date, contract_acquisition_price, contract_tc_fee_value, contract_iof_tax_value, contract_other_expenses_value, indexer_id→indexers (nullable), contract_monthly_interest_rate numeric(9,6), contract_maturity_years smallint, installment_code, installment_number smallint, contract_min_maturity_date, contract_max_maturity_date, face_value_original, face_value, acquisition_value (nullable), maturity_date_original, maturity_date, spread_over_indexer numeric(9,6), indexer_percentage numeric(9,6), spread_over_cdi numeric(8,6), ipoc text; unique(maturity_date, contract); idx(contract, maturity_date_original)
- `ntnis` — maturity_date, face_value_usd decimal(15,6)
- `cdbs` — issuer_id→entities, issuance_date, maturity_date, face_value, fgc_guarantee bool, indexer_id→indexers, spread_over_indexer, indexer_percentage, spread_over_cdi (nullable)
- `tokens` — strategy_id→token_strategies, structure_id→token_structures, issuance_count smallint, issuer_id→entities, issuer_code char(2), indexer_id→indexers (nullable), estimated_moic numeric(11,4), issuance_price, issuance_amount, offering_duration smallint (nullable), max_offering_date (nullable), internal_rate_of_return numeric(8,4), maturity_date (nullable), return_percentage_cdi numeric(12,8), minimum_issuance_amount, estimated_spread_over_cdi, estimated_spread_over_inflation, distributor varchar(100), referral_fee numeric(7,6), duration_months numeric(8,4), face_value numeric(11,2) (nullable)
- `securitizations` — document varchar(14) unique (nullable), underlying_asset_id→securitization_underlying_assets, issuance_number int, issuance_date, issuer_id→entities, trustee_id→entities, assignment_yield numeric(8,6), security_margin int

### Sub-tabelas de securitização
- `securitization_series` — **id int8 pk, FK→entities** (mesmo padrão de tabelas de ativo — não bigserial, id vem do entity criado antes), issuer_id→entities, issuance_number, series_number, seniority_id→seniorities, seniority_number smallint, indexer_id→indexers, indexer_percentage, spread_over_indexer, issuance_date, maturity_date (nullable), initial_price, quantity int, cash_sweep bool, offer_id→offers, register_id→registers (nullable), register_b3 bool; unique(issuer_id, issuance_number, series_number, seniority_id)
- `securitization_payment_schedules` — id smallint pk, securitization_id→entities, date, amortization_fraction, interest_payment bool; unique(id, securitization_id, date)
- `securitization_expenses` — id smallserial pk, securitization_id→entities, name_id→securitization_expense_names, type_id→securitization_expense_types, value, frequency_id→frequencies, billing_frequency_id→frequencies, provisioning_frequency_id→frequencies; unique(securitization_id, name_id)

### Posições e valuações
- `positions` — id bigserial pk, date timestamptz, holder_id→entities, asset_id→entities, lot_id int, financial_account_id→financial_accounts, transaction_type_id→transaction_types, variation decimal(18,6), **total_quantity [trigger: soma cumulativa de variation]**, block_id bigint, holder_bank_account_id→bank_accounts (nullable), counterparty_bank_account_id→bank_accounts (nullable), event_code text, payment_code, originator_id→entities (nullable), broker_id→entities (nullable), doc_id bigint, **last_position_flag [trigger]**, transaction_unit_price (nullable), trade_date (nullable); unique(date, holder_id, asset_id, financial_account_id); idx(asset_id, date DESC); idx(holder/asset/lot/fa, date, id) cumulative; idx(...DESC, id DESC) last_flag
- `valuations` — id bigserial pk, date timestamptz, asset_id→entities, lot_id int, methodology_id→valuation_methodologies, clean_price, accrued_interest (nullable), indexer_id→indexers (nullable), indexer_percentage, spread_over_indexer, spread_over_cdi, spread_over_inflation, cash_flow (nullable), currency_id→currencies, **last_valuation_flag [trigger]**, duration_years numeric(8,4) (nullable); unique(date, asset_id, lot_id, methodology_id); partial idx(asset_id) WHERE last_valuation_flag IS TRUE; idx(asset_id, methodology_id, lot_id, date DESC, id DESC)
- `expected_cash_flows` — id serial pk, entity_id→entities, date timestamptz, value, currency_id→entities (**FK para entities, não currencies — quirk**); unique(entity_id, date, currency_id)

### Outros
- `risks` — id int, from_id→entities (nullable), to_id→entities, date, risk_type_id→risk_types, min_term smallint, max_term smallint, min_concentration numeric(8,4), max_concentration numeric(8,4), min_spread numeric(8,4); unique(from_id, to_id, date)
- `curves` — id bigserial, date, curve_id→entities, parameter varchar(50), value numeric(18,6), parameter_type_id→parameter_types; unique(date, curve_id, parameter, parameter_type_id)
