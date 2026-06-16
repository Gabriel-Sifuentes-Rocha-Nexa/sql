# Plano de reconstrução dos CRs — worklist por data (Engine V2 / PROD)

> Fonte de verdade dos valores esperados: `tabela_juros_v1_v2.csv`, `comparacao_cash_flow_v1_v2.csv`, `tabela_restantes.csv`.
> FGTS-01 = piloto COMPLETO (não entra aqui). CONSORTIUMS-13 = OK (não entra).
> Conferência por (série E token): `clean` cai = `juros_V1`; `accrued` MANTÉM; `dirty` cai ~juros; série=token; 1 position AMORTIZATION; sem valuation forward indevido.

## Primeira divergência
**`2025-11-14` — FGTS-02, FGTS-03, FGTS-06** (GLITCH_ACCRUED: accrued revertido ~0.065; clean já certo).

## Legenda de tipo
- **GLITCH** — evento existe, `clean` certo, mas `accrued` foi revertido (dirty contaminado). Fix: corrigir accrued+cash_flow no row do evento (ou re-rodar a partir dele).
- **DIVERGE** — `clean_price` errado (V2 sub/super-amortizou). Fix: re-rodar (corrigir só cash_flow recria a inconsistência).
- **MISSING** — V2 nunca lançou o evento (só a diária, sem cash_flow). Fix: lançar via API.
- **CHECK** — drop bateu mas nível absoluto diverge; conferir depois de corrigir os vizinhos.

## Worklist mestre (ordenado por data)

| # | Data | CR(s) | Tipo | juros_V1 (= clean drop) | clean_after esperado | status |
|---|------|-------|------|------------------------|----------------------|--------|
| 1 | 2025-11-14 | FGTS-02 (NXFGTSH35-1) | GLITCH | 1.053923 | 94.123675 | ✅ re-rodado OK (accrued mantido 3.7768, dirty=V1, série=token) |
| 1 | 2025-11-14 | FGTS-03 (NXFGTSH35-2) | GLITCH | 1.268654 | 94.241843 | ✅ re-rodado OK (accrued mantido 3.2070, dirty=V1) |
| 1 | 2025-11-14 | FGTS-06 (NXFGTSI35-3) | GLITCH | 1.0783792 | 97.1780958 | ✅ re-rodado OK (accrued mantido 1.9831, dirty=V1) |
| 2 | 2026-03-16 | FGTS-08-01-SENIOR | MISSING | 13.53147639 | →92.5 | ⬜ |
| 2 | 2026-03-16 | FGTS-08-02-MEZZANINE | MISSING | 14.1042787 | →92.5 | ⬜ |
| 3 | 2026-04-17 | FGTS-08-01-SENIOR | DIVERGE/vencimento | 93.833296 | ~-0.44 (tratar à parte) | ⬜ |
| 3 | 2026-04-17 | FGTS-08-02-MEZZANINE | DIVERGE/vencimento | 93.958405 | ~-0.44 (tratar à parte) | ⬜ |
| 4 | 2026-04-23 | FGTS-08-03-SUBORDINATED | CHECK nível | 90 | 10 (V2 está 16.76, +6.76) | ⬜ |
| 5 | 2026-05-06 | FGTS-25 | DIVERGE | 5.26621213 | 94.73378787 (V2 está 96.20201) | ✅ re-run OK (sessão ant.) |
| 6 | 2026-05-07 | FGTS-23 | DIVERGE | 0.54213173 | 99.45786827 | ✅ RECONSTRUÍDO (taxa+início+freeze+2 amorts; = V1) 06-12 |
| 7 | 2026-06-03 | CONSORTIUMS-29 | cf-fix (cf=−clean) | 1.883998 | clean OK (20.09398120) | ✅ UPDATE cash_flow→1.883998 (série+token) 06-12 |
| 8 | 2026-06-08 | FGTS-02 | MISSING | 3.4969933 | 67.96133147 | ✅ bookado (var −36543.58) |
| 8 | 2026-06-08 | FGTS-03 | MISSING | 3.482028 | 68.63435600 | ✅ bookado (var −34820.28) |
| 8 | 2026-06-08 | FGTS-04 | MISSING | 3.723912 | 70.31663133 | ✅ bookado (var −55858.68) 06-12 |
| 8 | 2026-06-08 | FGTS-05 | MISSING | 3.204099 | 73.11639500 | ✅ bookado (var −80102.48) 06-12 |
| 8 | 2026-06-08 | FGTS-06 | MISSING | 2.864222 | 72.63146200 | ✅ bookado (var −71605.55) |
| 8 | 2026-06-08 | FGTS-10 | MISSING | 3.537675 | 74.83816400 | ✅ bookado (var −57664.10) 06-12 |
| 8 | 2026-06-08 | FGTS-12 | MISSING | 2.28792667 | 76.71559222 | ✅ bookado (var −20591.34) 06-12 |
| 8 | 2026-06-08 | FGTS-23 | MISSING | 4.827052 | 94.63081627 | ✅ bookado (var −48753.23; accrued=V1) 06-12 |
| 8 | 2026-06-08 | FGTS-25 | MISSING | 2.785041 | — | ✅ bookado (sessão ant.) |
| 9 | 2026-06-09 | FGTS-07 | MISSING | 3.35050292 | 72.12235242 | ✅ bookado (var −229509.45) 06-12 |
| 9 | 2026-06-09 | FGTS-15 | MISSING | 4.18211111 | 84.31008741 | ✅ bookado (var −28229.25) 06-12 |
| 9 | 2026-06-09 | CONSORTIUMS-29 | MISSING | 9.92027152 | 10.17370968 | ✅ bookado (var −203871.50) 06-12 |

## Resumo por CR (1ª divergência → ação)

| CR | 1ª divergência | tipo | demais ações |
|----|----------------|------|--------------|
| FGTS-02 | 2025-11-14 | GLITCH | + MISSING 06-08 |
| FGTS-03 | 2025-11-14 | GLITCH | + MISSING 06-08 |
| FGTS-06 | 2025-11-14 | GLITCH | + MISSING 06-08 |
| FGTS-08-01-SENIOR | 2026-03-16 | MISSING | + DIVERGE 04-17 |
| FGTS-08-02-MEZZANINE | 2026-03-16 | MISSING | + DIVERGE 04-17 |
| FGTS-08-03-SUBORDINATED | 2026-04-23 | CHECK | (depende de 08-01/02) |
| FGTS-25 | 2026-05-06 | DIVERGE | + MISSING 06-08 |
| FGTS-23 | 2026-05-07 | DIVERGE | + MISSING 06-08 |
| CONSORTIUMS-29 | 2026-06-03 | MISSING | + MISSING 06-09 |
| FGTS-04 | 2026-06-08 | MISSING | — |
| FGTS-05 | 2026-06-08 | MISSING | — |
| FGTS-10 | 2026-06-08 | MISSING | — |
| FGTS-12 | 2026-06-08 | MISSING | — |
| FGTS-07 | 2026-06-09 | MISSING | — |
| FGTS-15 | 2026-06-09 | MISSING | — |

## Notas de método
- ✅ **FGTS-02/03/06 RECONSTRUÍDOS E CURRENT (2026-06-11):** todos os amorts re-rodados/bookados (11-14, 12-08, 01-09, 02-10/11, 03-05, 04-07, 05-06/07, 06-08), dirty=V1 em todos, série=token idênticos, accruado até 06-11. Posições antigas (leftover) sobrescritas pelo upsert em cada data; 06-08 era MISSING (bookado novo). Pilotos 2/3/6 = OK junto com o FGTS-01.
- **GLITCH (02/03/06 @ 11-14):** ⚠️ CIRÚRGICO NÃO RESOLVE. O glitch revertou ~0.0666 de `accrued` em 11-14 e, como o accrued **acumula sem reset** nesses FGTS, o gap PROPAGA e COMPÕE forward (`price_off` vai de -0.0666 em 11-14 até -0.072 em 05-07; antes de 11-14 era ~1e-7). O `clean` bate, mas `accrued`/`dirty` está baixo desde 11-14 até hoje (a correção dos 78 SIM mexeu só no `cash_flow`, nunca no accrued). ⇒ **re-run a partir de 11-14 (opção B, igual FGTS-01)** — apaga forward, re-roda evento a evento. Datas de re-run abaixo.
  - FGTS-02: 11-14, 12-08, 01-09, 02-11, 03-05, 04-07, 05-07, +06-08(MISSING)
  - FGTS-03: 11-14, 12-08, 01-09, 02-10, 03-05, 04-07, 05-06, +06-08(MISSING)
  - FGTS-06: 11-14, 12-08, 01-09, 02-10, 03-05, 04-07, 05-06, +06-08(MISSING)
- **FGTS-08 (03-16 + 04-17):** caso mais complexo — V2 não lançou 03-16 e "lumpou" no 04-17; o 04-17 é evento de vencimento (clean→~-0.44 no próprio V1). Deep-dive antes de re-rodar.
- **MISSING junho (06-08/09):** é só o amort mais recente que o engine não rodou ainda — lançar via API normalmente.
- ✅ **LOTE DE JUNHO COMPLETO (2026-06-12):** FGTS-04/05/10/12 (06-08), FGTS-07/15 (06-09), CONSORTIUMS-29 (cf-fix 06-03 + amort 06-09). Numa passada só: apaguei as dailies forward (`apaga_dailies_lote_junho_PROD.sql`, 36 rows, histories) + cf-fix CONS-29 06-03 (`corrige_cf_0603_CONS29_PROD.sql`, 2 rows, histories), Gabriel bookou os 7, rodou accrual 1×. Todos: clean cai=juros_V1, accrued mantém, cash_flow=+juros, série=token, 1 position AMORTIZATION (var=−cash_flow×qty), accruado até 06-11 (EOD). CONS-29 06-09 confere com a soma das 6 REDEMPTIONs de cota (203.871,50).
- ⚠️ **A accrual NÃO sobrescreve dailies forward, só preenche buraco** (confirmado pelo Gabriel). Por isso, antes de bookar um amort MISSING que já tem dailies accruadas à frente, APAGAR as dailies `> data-do-amort 00:00` (mantendo o seed pré-amort), bookar, e re-accruar.
- ✅ **FGTS-23 RECONSTRUÍDO (2026-06-12) — eram 4 bugs distintos:**
  1. **TAXA ERRADA (o grande):** V2 ingeriu `securitization_series.spread_over_indexer=0.16` (16.00%, da MÃE `entities` spv → `series[].series_fixed_rate`) em vez de **0.1645** (16.45%, da SÉRIE `securities` spv_series `series_fixed_rate`). V1 precifica com 0.1645. Prova: accrued/dia 0.0589=16% (V2 errado) vs 0.0605=16.45% (V1). Fix: `corrige_taxa_FGTS23_PROD.sql` (UPDATE série 1057325, histories).
  2. **SHIFT de 1 dia no início:** V2 largava 03-03, V1 03-04. NÃO é universal (quase todos os CRs batem 0d; só FGTS-23=1d e **FGTS-41=3d**). Cessão (01-30) e emissão (02-13) idênticas V1=V2 → não dá p/ corrigir por dado nem re-accruar (determinístico). **Fix: FORÇAR o início** (`forca_inicio_FGTS23_PROD.sql`): alinhei 03-03/04/05 accrued ao V1 (UPDATE) + apaguei 03-06; o engine reconstruiu dali e 03-06 saiu = V1 (âncora pegou).
  3. **FREEZE 04-15→04-27:** era **buraco de job** (valuator não rodou), NÃO cálculo — re-accruar com taxa+início certos **preencheu batendo V1 ao centavo**.
  4. **Amorts 05-07 (5475.53) + 06-08 (48753.23):** o engine **carrega a última daily no amort** (não accrua o dia). 05-07: V1 accruou o dia → corrigi accrued cirúrgico (`forca_accrued_0507`, 2.63268868→2.6947317). 06-08: V1 NÃO accruou (usou sexta 06-05 pós fim-de-semana) → parar a accrual em 06-07 e bookar deu 3.93690625=V1 natural (sem fix).
  Resultado: current 06-11, accrued=V1 (8 casas), dirty ~4e-7 (rounding amort 2 casas), série=token sync 119/119. Métodos novos: `inspect_fgts23_v1_v2.py`, `compara_inicio_accrual_v1_v2.py`.
- ✅ **FGTS-41 RECONSTRUÍDO (2026-06-12):** mesmos 2 bugs do 23, mais simples (novo, sem amort/freeze). Taxa 0.1824 (mãe) → **0.1825** (série=V1); início forçado (zerei 06-05/06/07, V1 só accrua 06-08 — feriado Corpus Christi 06-04 + fds; apaguei 06-08+, engine refez). Resultado: V2 = V1 **EXATO 8 casas** (sem resíduo, não tem amort). `forca_inicio_e_taxa_FGTS41_PROD.sql` (série 1400751/token 1400752/NXFGTSF31-1, qty 50000). Confirma o método "rate + forçar início" como reutilizável.
- ✅ **FGTS-08 RECONSTRUÍDO (2026-06-16) — era redenção ANTECIPADA (não vencimento; vence 2031/2040), CDI multi-tranche.** SR/MZ: amort 03-15 (7,5% princ.+juros) perdida + redenção 04-17 bugada (cash_flow=-clean). Apaguei >03-15, Gabriel re-bookou amort/accrual/redenção; o amort com `interest_payment` precisou fix cirúrgico (API rejeita `interest_payment:true`): mover evento p/ 03-16 + zerar accrued + cash_flow=principal+juros, e corrigir o caixa em positions (valor pago = (princ+juros)×qty cheia; perna do senior nem tinha sido criada). Redenção dupla colidiu no slot de caixa 16:00:00 (unique) → movi a perna do senior p/ 16:00:01. SUB: só o preço do dia da amort (04-23=10=V1), accrual ignorado. V2=V1 exato. Detalhe em [[project_cash_flow_correction]] e [[reference_v2_maturity_redemption]].
- **RESTAM:** nada de FGTS-08. (Pendentes do projeto: CONS-40 bloqueado até integralização.)
