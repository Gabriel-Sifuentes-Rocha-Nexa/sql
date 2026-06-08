# Fluxo de caixa pela característica da série

Calcula o fluxo de caixa de cada série **a partir das características da própria
série** (último PU, taxa, indexador, datas) — **não** a partir dos ativos de
lastro. É a versão Python do que o util
[`v1v2/queries/utils/fluxo_caixa_por_serie.sql`](../v1v2/queries/utils/fluxo_caixa_por_serie.sql)
faz só para o caso bullet.

## Método

Pega-se o **último PU sujo** (`clean_price + accrued_interest` na linha com
`last_valuation_flag = TRUE`) e leva-se a **valor futuro** até o vencimento pela
taxa contratual.

**Por que isso é fiel:** está validado (ver `validate.py`, T2) que, entre eventos
de caixa, o engine acretua o PU **exatamente** na taxa contratual — a variação
diária bate com `(1+taxa)^(1/252) − 1` com erro de ~`1e-10`. Logo o accrual
abaixo reproduz a própria mecânica do engine, não é aproximação.

| Indexador | Fator de accrual | Day count |
|-----------|------------------|-----------|
| PREFIXADO | `(1+spread)^(DU/252)` | DU 252 (calendário ANBIMA/B3 da tabela `holidays`) |
| CDI | `(1 + ((1+r)^(1/252)−1)·pct)^DU · (1+spread)^(DU/252)` | DU 252; `r` = DI forward interpolado da `curve_id=10` no prazo restante |
| DOLLAR_PTAX / SOFR | `(1+spread)^(dias360/360)` · FX | 30/360 (aritmética pura) |

### Bullet vs amortizante

- **Bullet** (sem amortização parcial): 1 resgate no vencimento =
  `PU · fator · quantidade`. **Exato.** (82 das 101 séries não-subordinated.)
- **Amortizante** (FGTS e tranches de consórcio — o PU cai em degraus quando
  devolve principal): 19 séries. Tratamento:
  - **Realizado** (`is_projected = False`): cada degrau do PU vira um evento de
    caixa já distribuído — reconstruído da própria valuation da série.
  - **Futuro** (`is_projected = True`): a amortização futura do FGTS é dirigida
    pelo **lastro** e **não** é característica recuperável da série (o
    `securitization_payment_schedules` não tem chave de série, usa fração do
    saldo e tem várias linhas por data — inutilizável por série). Então projeta-se
    pela **fração mensal de amortização observada no histórico de PU**
    (estratégia `extrapolate`, default) ou como **teto bullet** (estratégia
    `bullet`). É uma premissa de modelo, sinalizada em cada linha (`note`).

## Como rodar

```bash
py -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt

.venv\Scripts\python validate.py          # validações contra o banco
.venv\Scripts\python run.py               # gera output/cash_flows.csv
```

Opções do `run.py`:

| Flag | Default | Descrição |
|------|---------|-----------|
| `--asof YYYY-MM-DD` | último PU | data-base do accrual e da curva |
| `--calendar` | `anbima` | calendário de DU (`anbima`/`b3`) |
| `--strategy` | `extrapolate` | projeção do futuro dos amortizantes (`extrapolate`/`bullet`) |
| `--name PADRÃO` | — | filtro ILIKE pelo nome da série |
| `--all` | — | inclui séries `SUBORDINATED` |
| `--threshold` | `0.005` | queda de PU que marca amortização |
| `--out` | `output/cash_flows.csv` | caminho do CSV |

Saída (`cash_flows.csv`): uma linha por evento de caixa, com `series_id`,
`series_name`, `indexer`, `classification`, `date`, `month`, `amount`,
`currency`, `kind` (`amortization`/`redemption`), `is_projected`, `note`.

### Qual PU? (metodologia de valuation)

Uma série pode ter **vários PUs simultâneos** com `last_valuation_flag = TRUE`,
um por metodologia (`amortized_cost`, `mark_to_model`, `pu_nexa`, `pu_daycoval`,
`amount_*`, `face_value`…). Escolhe-se **um PU por unidade** por prioridade
(`db.PU_METHODOLOGY_PRIORITY`), preferindo `amortized_cost` (o PU de curva que
acretua na taxa contratual — premissa do método). As séries que não têm
`amortized_cost` (FIDC) caem em `pu_nexa` (marca da casa). Resultado atual:
91 séries em `amortized_cost`, 10 em `pu_nexa`. As metodologias de **total**
(`amount_*`) e **par** (`face_value`) são excluídas de propósito (não são PU por
unidade). A metodologia usada por série vai na coluna `methodology` do CSV.
**Decisão de negócio:** se preferirem `pu_daycoval`/`mark_to_market`/etc., é só
reordenar a prioridade.

## Limitações / pendências

- **CDI**: usa `curve_id=10` como DI forward (confirmado: `parameter` = DU base
  252, `value` = taxa a.a. ~14,3%). Vale o time confirmar que esse é o curve_id
  oficial; trocar é 1 constante (`db.DI_CURVE_ID`).
- **FGTS amortizante (futuro)**: extrapolação, não o cronograma real. Para
  precisão, plugar a amortização vinda do lastro (queries 09/13) — fica como
  próximo passo.
- **USD (DOLLAR_PTAX/SOFR)**: day-count 30/360 pronto, mas falta o FX
  (`exchange_rates`) para converter; e **não há série USD na cópia local**.
- **IPCA+ e outros índices**: precisam projeção de inflação (`curves`); sem dado
  local, saem como `unsupported`.

## Arquitetura

```
fluxo_caixa/
  db.py         conexão LOCAL read-only + queries (series, valuations, holidays, curva DI)
  daycount.py   calendário de DU 252 (da tabela holidays) e 30/360
  rates.py      provedores de taxa forward (curva DI interpolada / flat)
  model.py      Series e CashFlow (dataclasses)
  builders.py   fatores de accrual, classificação bullet/amortizante, builders
  engine.py     orquestra tudo -> DataFrame
run.py          CLI
validate.py     validações (DU vs SQL, accrual vs taxa, amostras)
```

## Segurança

Opera **somente** na cópia **LOCAL** do engine (`127.0.0.1:5432/engine`),
sessão **read-only** (`set_session(readonly=True)`), só `SELECT`. A conexão
recusa qualquer host não-local e **ignora** a `V1_DATABASE_URL` (Supabase prod).
Nunca toca produção.
