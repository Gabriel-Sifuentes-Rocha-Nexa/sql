-- ============================================================
-- util. Nome do token FGTS no Engine V1 (companion do _v2.sql)
-- ------------------------------------------------------------
-- Banco ALVO: V1 (Supabase — `securities` + `metadata JSONB`, UUIDs via aux_id)
-- NAO roda no run_query.py (esse aponta pro V2). Rode no seu client do V1.
--
-- Objetivo: para os mesmos CRs do _v2.sql, achar a SERIE do V1 e o NOME do
-- TOKEN no V1, para comparar com o nome do token no V2 e descobrir o que o
-- V2 codificou errado.
--
-- Modelo V1 (ver v1_metadata_entities.md / v1_metadata_other_assets.md):
--   entities  type='spv'                         = a mae (CR-FGTS-N)
--   securities type='spv_series'                 = as series (tranches)
--      vinculo a mae: metadata->>'spv_aux_id' = spv.aux_id
--   securities type='token'                      = o token
--      vinculo a serie: algum item de metadata->'composition' tem
--      asset_aux_id = serie.aux_id   (padrao da query "Public Offer" do V1,
--      que e' keyed pelo token e cai na spv_series via composition).
--
-- PONTOS A VALIDAR (estou escrevendo sem acesso ao V1):
--   1) entities tem coluna `type` e securities tem coluna `type` (as queries
--      V1 do projeto usam s.type='token'); se o nome da coluna divergir, ajuste.
--   2) A mae e' selecionada pelo nome via regex (tolera zero-padding:
--      CR-FGTS-1 ou CR-FGTS-01). Confirme com os nomes que o _v2.sql devolveu.
--   3) O token CR liga na SERIE pela composition (assumido). Se token_v1_*
--      vier NULL, o vinculo pode ser por metadata->>'issuer' (= a mae) ou a
--      composition pode apontar as PARCELAS (caso "Nao CR") — me avise.
-- ============================================================
WITH alvo(cr_num) AS (
    VALUES (1), (4), (5), (6), (8)        -- numeros dos CR-FGTS-N (ajuste se preciso)
)
SELECT
    spv.name                                          AS mae_cr,
    ser.name                                          AS serie_v1,
    ser.code                                          AS serie_v1_code,
    ser.full_name                                     AS serie_v1_full_name,
    sc.series_code                                    AS serie_code_no_spv,   -- com sufixo "-NN" tipico do V1
    (ser.metadata->>'series_number')                  AS series_number,
    (ser.metadata->>'series_type')                    AS series_type,
    (ser.metadata->>'series_maturity_date')           AS series_maturity_date,
    (ser.metadata->>'series_issuance_date')           AS series_issuance_date,
    -- >>> o que queremos: o nome do token no V1 <<<
    tok.name                                          AS token_v1_name,
    tok.code                                          AS token_v1_code,
    tok.full_name                                     AS token_v1_full_name,
    (tok.metadata->>'serie')                          AS token_serie_count,
    (tok.metadata->>'last_maturity_date')             AS token_last_maturity_date
FROM entities spv
JOIN alvo a
  ON (regexp_match(spv.name, '^CR-FGTS-0*([0-9]+)$'))[1]::int = a.cr_num
JOIN securities ser
  ON ser.type = 'spv_series'
 AND ser.metadata->>'spv_aux_id' = spv.aux_id::text        -- comparacao textual (evita cast uuid)
LEFT JOIN LATERAL (
    SELECT s->>'series_code' AS series_code
    FROM jsonb_array_elements(                              -- guarda: so itera se for array
             CASE WHEN jsonb_typeof(spv.metadata->'series') = 'array'
                  THEN spv.metadata->'series' ELSE '[]'::jsonb END) s
    WHERE (s->>'series_number') = (ser.metadata->>'series_number')
      AND (s->>'series_type')   = (ser.metadata->>'series_type')
    LIMIT 1
) sc ON TRUE
LEFT JOIN securities tok
  ON tok.type = 'token'
 AND EXISTS (
       SELECT 1
       FROM jsonb_array_elements(                           -- guarda: so itera se for array
                CASE WHEN jsonb_typeof(tok.metadata->'composition') = 'array'
                     THEN tok.metadata->'composition' ELSE '[]'::jsonb END) c
       WHERE c->>'asset_aux_id' = ser.aux_id::text          -- comparacao textual
     )
WHERE spv.type = 'spv'
ORDER BY a.cr_num, ser.name;

-- Como cruzar com o V2: case por (mae_cr + series_number + series_type/seniority
-- + maturity). Para CR-01/04/05/06 deve haver 1 serie => 1 token; compare
-- token_v1_name  x  token_name(V2).
--
-- RESULTADO (V1 Supabase, read-only, 2026-06-08). serie_v1(name) vem NULL no V1;
-- o identificador da serie e' o code/full_name (= series_code, minusculo + sufixo -NN):
--   CR-01 -> CR-FGTS-01-01-single-01       -> NXFGTSJ34-1     | V2: NXFGTSL34-1   (DIFERE: letra J vs L; venc Dez => L e' o certo)
--   CR-04 -> CR-FGTS-04-01-single-01       -> NXFGTSI35-1     | V2: NXFGTSI35-4   (DIFERE: sufixo 1 vs 4)
--   CR-05 -> CR-FGTS-05-01-single-01       -> NXFGTSI35-2     | V2: NXFGTSI35-5   (DIFERE: sufixo 2 vs 5)
--   CR-06 -> CR-FGTS-06-01-single-01       -> NXFGTSI35-3     | V2: NXFGTSI35-6   (DIFERE: sufixo 3 vs 6)
--   CR-08 -> 01-senior-01     -> NXFGTSSRL31-8.1 | == V2
--            02-mezzanine-02  -> NXFGTSMZL31-8.2 | == V2
--            03-subordinated-03 -> NXFGTSJRL40-8.3 | == V2  (CR-08 bate 100%)
-- Sufixo V1 dos singles = sequencia por balde de mesmo vencimento, na ordem de
-- emissao (I35: CR-04=1, CR-05=2, CR-06=3). V2 troca pelo nº do CR. Esse e' o bug.
