---
name: Reference — V1 FGTS Metadata & V1→V2 Field Mapping
description: Exact structure of securities.metadata JSONB for parcela_fgts type, plus field-level V1→V2 mapping
type: reference
tags: [tipo/referência, conceito/migração, team/engine, produto/fgts]
resumo: "Estrutura JSONB de parcela_fgts em V1 e mapeamento campo a campo para tabela V2 fgts — incluindo campos que vêm do arquivo de elegibilidade"
---

## Tipo V1

`securities.type = 'parcela_fgts'` → mapeia para tabela V2 `fgts` (+ row em `entities`)

Total: ~1.126.453 records. Tiers de população:
- **~1.126.453 records**: 14 campos core
- **~1.111.124 records**: campos estendidos (parcela_code, spread_over_cdi, nome_cessionario, etc.)
- **~679.820 records**: também têm new_yield, new_yield_date (reprecificação)
- **~15.329 records**: também têm data_emissao, valor_aquisicao_sem_custos, etc.

---

## Elegibilidade e Gates

Gates aplicados durante a ingestão de parcelas. Parcelas que passam em todos os gates são inseridas em V2 `fgts` com `status_id = 'ativa'`; rejeitadas são descartadas.

| Gate | Critério |
|---|---|
| Taxa de cessão mínima | configurada por operação |
| Valor de contrato mínimo | configurado por operação |
| Janela de vencimento | maturity > hoje + 15 dias |
| Verificação antifraude | parceiro confirma disponibilidade do saldo FGTS do tomador |

**Tarifas típicas (podem variar por deal)**:
- Tomador: ~1,69% a.m.
- Bancarizador (taxa de cessão): 1,37–1,45% a.m.

---

## Chaves do Metadata

```
metadata = {
  -- CAMPOS CORE (todos os ~1.1M records)
  "originator":          string -- nome do originador → originator_id entity lookup
  "originator_document": string -- CNPJ do originador → originator_id entity lookup
  "cedente":             string -- nome do cedente → assignor_id entity lookup
  "cedente_documento":   string -- CNPJ do cedente → assignor_id entity lookup
  "contrato":            number -- identificador do contrato → contract (varchar)
  "data_cessao":         string -- data de cessão → assignment_date
  "data_vencimento":     string -- data de vencimento da parcela (base para maturity_date_original/maturity_date)
  "dc":                  number -- dias corridos até vencimento (computado, não armazenado)
  "du":                  number -- dias úteis até vencimento (computado, não armazenado)
  "sacado_documento":    string -- CPF do obrigado (V1 apenas — NÃO armazenado em V2 fgts; supersedido pelo arquivo de elegibilidade)
  "sacado_nome":         string -- nome do obrigado (V1 apenas — NÃO armazenado em V2 fgts)
  "status":              string -- "aberta" (aberta) | outros → status_id FK
  "tx_cessao":           float  -- taxa de cessão; NÃO usada diretamente — spread_over_indexer é calculado via IRR
  "valor_aquisicao":     float  -- valor de aquisição → acquisition_value
  "valor_nominal":       float  -- valor nominal/face → face_value

  -- CAMPOS ESTENDIDOS (~1.1M records)
  "parcela_code":          string -- código da parcela (formato: "CNPJ/CODE/DATE") → installment_code
  "spread_over_cdi":       float  -- spread sobre CDI → spread_over_cdi (V2 também deriva via IRR + curva ETTJ)
  "nome_cessionario":      string -- nome do cessionário → assignee_id entity lookup
  "doc_cessionario":       string -- CNPJ do cessionário → assignee_id entity lookup
  "numero_parcela":        number -- número da parcela → installment_number
  "sacado_nascimento":     string -- data de nascimento do obrigado → obligor_birthday_date
  "taxa_juros_contratada": float  -- taxa de juros mensal contratada → contract_monthly_interest_rate
  "tipo_juros":            string -- "pré-fixado" → indexer_id = PREFIXADO
  "dat_emissao":           string -- data de emissão → contract_emission_date
  "valor_de_cessao":       float  -- valor de cessão → contract_acquisition_price
  "valor_de_desembolso":   float  -- valor de desembolso → contract_disbursement_value
  "valor_de_emissao":      float  -- valor de emissão → face_value_original ou contract_original_debt_value
  "valor_iof":             float  -- IOF → contract_iof_tax_value
  "valor_outras_despesas": float  -- outras despesas → contract_other_expenses_value
  "valor_tc":              float  -- taxa TC → contract_tc_fee_value

  -- CAMPOS DE REPRECIFICAÇÃO (~680K records)
  "new_yield":      float  -- yield reprecificado
  "new_yield_date": string -- data do evento de reprecificação
}
```

---

## Colunas V2 que NÃO vêm do metadata V1

Estes campos vêm do **arquivo de elegibilidade FGTS** (`Relatorio_Nexa_elegibilidade_*.csv`), não dos dados V1 do Supabase:

| Coluna V2 | Campo no arquivo de elegibilidade |
|---|---|
| `cef_uuid` | `chave_reserva_cef` (opcional) |
| `cef_protocol` | `num_protocolo_cef` (opcional) |
| `obligor_bank` | `nome_instituto_bancario` |
| `obligor_bank_code` | `cod_instituto_bancario` |
| `obligor_uf` | `uf_sacado` |
| `obligor_city` | `cidade_sacado` |
| `obligor_neighbourhood` | `bairro_sacado` |
| `obligor_street` | `endereco_sacado` |
| `obligor_zip_code` | `cep_sacado` |
| `obligor_gender` | `sexo_sacado` |
| `obligor_birthday_date` | `dat_nascimento_sacado` |
| `contract_min_maturity_date` | `dat_vencimento_min` |
| `contract_max_maturity_date` | `dat_vencimento_max` |

**`cession_id`** — não vem nem do V1 nem do arquivo de elegibilidade. É um **contador sequencial de batch**: todos os records de um único batch ETL compartilham o mesmo `cession_id`. Não existe tabela `cessions` — é um conceito V2 para agrupar um lote de recebíveis.

---

## Campos calculados — Lógica confirmada

### `maturity_date_original` e `maturity_date`
Derivados de `data_vencimento` usando lógica de dias úteis:
```
maturity_date_original = primeiro dia útil EM ou APÓS data_vencimento (n=0: mantém se já é DU)
maturity_date          = 1 dia útil ADICIONAL após maturity_date_original
```

### `spread_over_indexer` e `indexer_percentage`
NÃO derivados diretamente de `tx_cessao`. Calculados via IRR:
```
spread_over_indexer = IRR(
    days    = dias_corridos_até_vencimento,
    inflow  = acquisition_value,
    outflow = face_value,
    adjust_period = 360
)
indexer_percentage = 0   -- sempre 0 para FGTS PREFIXADO
indexer = 'PREFIXADO'
```

### `spread_over_cdi`
Derivado de `spread_over_indexer` usando a curva ETTJ:
```
spread_over_cdi = (1 + spread_over_indexer) / (1 + ettj) - 1
```

---

## Mapeamento completo V1 → V2

| Fonte V1 | Coluna V2 `fgts` | notas |
|---|---|---|
| `originator` + `originator_document` | `originator_id` | entity lookup |
| `cedente` + `cedente_documento` | `assignor_id` | entity lookup |
| `nome_cessionario` + `doc_cessionario` | `assignee_id` | entity lookup |
| `contrato` | `contract` | cast varchar |
| `data_cessao` | `assignment_date` | date |
| `dat_emissao` | `contract_emission_date` | date |
| `data_vencimento` → cálculo dia útil | `maturity_date_original` | ajuste n=0 DU |
| `data_vencimento` → cálculo dia útil | `maturity_date` | n=1 DU após original |
| `sacado_nascimento` / elegibilidade | `obligor_birthday_date` | date |
| `tipo_pessoa_sacado` / elegibilidade | `obligor_person_type` | char(1) |
| `taxa_juros_contratada` | `contract_monthly_interest_rate` | % mensal |
| `tipo_juros` → "PREFIXADO" | `indexer_id` | FK indexers |
| `parcela_code` | `installment_code` | varchar(50) |
| `numero_parcela` | `installment_number` | smallint |
| `valor_de_emissao` | `face_value_original` | decimal |
| `valor_nominal` | `face_value` | decimal |
| `valor_aquisicao` | `acquisition_value` | decimal |
| `valor_de_cessao` | `contract_acquisition_price` | decimal |
| `valor_tc` | `contract_tc_fee_value` | decimal |
| `valor_iof` | `contract_iof_tax_value` | decimal |
| `valor_outras_despesas` | `contract_other_expenses_value` | decimal |
| `valor_de_desembolso` | `contract_disbursement_value` | decimal |
| `spread_over_cdi` (V1) / IRR+ETTJ | `spread_over_cdi` | derivado |
| Cálculo IRR | `spread_over_indexer` | não de tx_cessao |
| 0 (constante) | `indexer_percentage` | sempre 0 para FGTS PREFIXADO |
| `status` | `status_id` | FK statuses |
| contador sequencial de batch | `cession_id` | sem fonte V1 |
| elegibilidade `chave_reserva_cef` | `cef_uuid` | opcional |
| elegibilidade `num_protocolo_cef` | `cef_protocol` | opcional |
| elegibilidade `nome_instituto_bancario` | `obligor_bank` | |
| elegibilidade `cod_instituto_bancario` | `obligor_bank_code` | |
| elegibilidade `uf_sacado` | `obligor_uf` | |
| elegibilidade `cidade_sacado` | `obligor_city` | |
| elegibilidade `bairro_sacado` | `obligor_neighbourhood` | |
| elegibilidade `endereco_sacado` | `obligor_street` | |
| elegibilidade `cep_sacado` | `obligor_zip_code` | |
| elegibilidade `sexo_sacado` | `obligor_gender` | |
| elegibilidade `dat_vencimento_min` | `contract_min_maturity_date` | |
| elegibilidade `dat_vencimento_max` | `contract_max_maturity_date` | |
