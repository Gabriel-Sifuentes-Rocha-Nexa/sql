---
name: Reference — Engine V1 (Supabase) Schema
description: Full DDL of the V1 Supabase database — central pattern, key tables, and V1→V2 transformation rules
type: reference
tags: [tipo/referência, conceito/migração, team/engine]
resumo: "DDL completa do banco V1 (Supabase): tabelas-chave, padrão JSONB genérico, e regras de transformação V1→V2"
---

## Padrão central do V1

Todos os ativos vivem em `securities` com coluna `metadata JSONB`. Todas as referências entre entidades usam UUIDs via tabela bridge `aux_ids`. Em V2 isso foi substituído por tabelas tipadas por asset class e IDs inteiros.

```sql
-- Bridge table: maps integer IDs to UUIDs
CREATE TABLE public.aux_ids (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  ref bigint NOT NULL,
  source text NOT NULL
);

-- Named entities (funds, companies, counterparties)
CREATE TABLE public.entities (
  id integer PRIMARY KEY,
  name text NOT NULL,
  type text NOT NULL,            -- FK entities_type.type
  aux_id uuid UNIQUE NOT NULL,   -- FK aux_ids
  metadata jsonb
);

-- All assets (securities, tokens, CDBs, etc.) in one generic table
CREATE TABLE public.securities (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  aux_id uuid UNIQUE NOT NULL,   -- FK aux_ids
  name text UNIQUE,
  full_name text NOT NULL,
  code text NOT NULL,
  type text,                     -- FK securities_type.type
  metadata jsonb                 -- all asset-specific fields stored here
);

-- Portfolio positions (holdings)
CREATE TABLE public.positions (
  id bigint PRIMARY KEY,
  position_date date NOT NULL,
  holder_aux_id uuid NOT NULL,   -- FK aux_ids → entity
  asset_aux_id uuid NOT NULL,    -- FK aux_ids → security
  amount numeric NOT NULL,
  available numeric NOT NULL,
  metadata jsonb
);

-- Valuations (marks, prices)
CREATE TABLE public.valuations (
  id integer PRIMARY KEY,
  valuation_date date NOT NULL,
  aux_id uuid NOT NULL,          -- FK aux_ids → security or entity
  value numeric,
  type text NOT NULL,            -- FK valuations_type.type
  metadata jsonb
);

-- Transactions
CREATE TABLE public.transactions (
  id integer PRIMARY KEY,
  transaction_date date NOT NULL,
  from_aux_id uuid NOT NULL,
  asset_aux_id uuid NOT NULL,
  to_aux_id uuid,
  price numeric NOT NULL,
  amount numeric NOT NULL,
  type text NOT NULL,            -- FK transactions_type.type
  metadata jsonb,
  position_id bigint             -- FK positions
);

-- Ownership tracking
CREATE TABLE public.ownership (
  id integer PRIMARY KEY,
  ownership_date date NOT NULL,
  owner_aux_id uuid NOT NULL,
  asset_aux_id uuid NOT NULL,
  value numeric NOT NULL,
  type text NOT NULL,            -- FK ownership_type.type
  metadata jsonb
);

-- Ratings
CREATE TABLE public.ratings (
  id integer PRIMARY KEY,
  from_aux_id uuid,
  to_aux_id uuid NOT NULL,
  rating_date date NOT NULL,
  value text NOT NULL,
  metadata jsonb
);

-- Holidays
CREATE TABLE public.holidays (
  id bigint PRIMARY KEY,
  data date NOT NULL,            -- NOTE: renamed to 'date' in v2
  descricao text NOT NULL,       -- NOTE: renamed to 'description' in v2
  calendario text NOT NULL       -- NOTE: renamed to 'calendar' in v2; now an enum
);

-- Logs
CREATE TABLE public.logs (
  id integer PRIMARY KEY,
  protocol text NOT NULL,
  begin_date timestamptz NOT NULL,
  end_date timestamptz,
  duration_seconds integer,
  status text NOT NULL CHECK (status IN ('success','failed')),
  error_message text,            -- NOTE: renamed to 'message' in v2
  details jsonb                  -- NOTE: dropped in v2
);

-- API ingestion queue (v1-specific, no v2 equivalent)
CREATE TABLE public.API_event_ingest (
  id bigint PRIMARY KEY,
  event_type text NOT NULL,
  event_id text NOT NULL,
  event_instance_id text UNIQUE NOT NULL,
  cota_codigo text NOT NULL,
  received_at timestamptz DEFAULT now(),
  status text DEFAULT 'pending',
  locked_at timestamptz,
  locked_by text,
  processed_at timestamptz,
  payload jsonb NOT NULL,
  error jsonb,
  child_result jsonb,
  bypass_validation boolean DEFAULT false
);

-- Type/category lookup tables (text-based in v1, integer FKs in v2)
CREATE TABLE public.entities_type (type text UNIQUE PRIMARY KEY, ...);
CREATE TABLE public.securities_type (type text UNIQUE PRIMARY KEY, ...);
CREATE TABLE public.transactions_type (type text UNIQUE PRIMARY KEY, ...);
CREATE TABLE public.valuations_type (type text UNIQUE PRIMARY KEY, ...);
CREATE TABLE public.ownership_type (type text UNIQUE PRIMARY KEY, ...);
CREATE TABLE public.categories (id bigint, category text UNIQUE, type text, ...);
CREATE TABLE public.categories_type (type text UNIQUE, ...);
CREATE TABLE public.securities_categories (aux_id uuid, category bigint, hierarchy bigint, ...);
```

## Regras de transformação V1 → V2

| Conceito V1 | Equivalente V2 |
|---|---|
| `securities.metadata JSONB` | Tabela tipada por asset class (`consortiums`, `fgts`, `ntnis`, etc.) |
| `aux_ids` UUID bridge | Removida — V2 usa integer IDs em todo lugar |
| `entities.aux_id` (UUID) | `entities.id` (integer, SERIAL) |
| `positions.holder_aux_id` / `asset_aux_id` | `positions.holder_id` / `asset_id` (integer FK para entities) |
| `valuations.aux_id` | `valuations.asset_id` (integer FK para entities) |
| `logs.error_message` | `logs.message` |
| `logs.details JSONB` | Removido em V2 |
| `holidays.data` / `descricao` / `calendario` | `holidays.date` / `description` / `calendar` (enum: anbima\|b3) |
| Tipos FK texto (`type text`) | Integer FK IDs com tabelas de lookup |
| `API_event_ingest` | Sem equivalente direto em V2 |
| `ownership` table | Sem equivalente direto em V2 |
| `ratings` table | Tabela `risks` (estrutura diferente) |
