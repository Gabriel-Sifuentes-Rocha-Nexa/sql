-- ============================================================================
-- Apagar posições (parcela_fgts / originador FLAMEX / holder FIDC NXFS) de HOJE
-- Banco ALVO: V1 (Supabase — `securities` + `metadata JSONB`, UUIDs via aux_id)
-- Tabela alvo: public.positions  (deletar SOMENTE do V1, conforme combinado)
-- Data alvo ("hoje"): 2026-06-01
--
-- Critérios (conforme alinhado):
--   asset_aux_id  -> securities.type = 'parcela_fgts'            (ref: v1_metadata_fgts.md)
--                    AND securities.metadata->>'originator' = FLAMEX
--   holder_aux_id -> entity 'FIDC NXFS' (nome exato)
--   position_date -> 2026-06-01 (hoje)
--   amount        -> 1
--   available     -> 1
--
-- PONTOS A VALIDAR antes do COMMIT:
--   1) Originador: uso ILIKE '%FLAMEX%' em metadata->>'originator' (tolerante a
--      caixa/espaços). Confira no PASSO 1 se o `originator` casa só o que você espera;
--      se souber o nome exato, troque por igualdade (=).
--   2) FK: v1.transactions.position_id referencia positions(id). Se houver transações
--      apontando para essas posições, o DELETE pode falhar (FK) ou deixar órfãos.
--      Rode o PASSO 1b. Você pediu p/ apagar SÓ positions — não toco em transactions.
--
-- COMO USAR:
--   PASSO 1  -> rode o SELECT de preview e confira EXATAMENTE as linhas-alvo.
--   PASSO 1b -> (opcional) confira transações relacionadas (FK).
--   PASSO 2  -> roda em transação com ROLLBACK por padrão (NÃO apaga nada).
--               Depois de validar, troque ROLLBACK por COMMIT.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- PASSO 1 — PREVIEW (não apaga nada). Confira as linhas que serão deletadas.
-- ----------------------------------------------------------------------------
WITH params AS (
    SELECT
        DATE '2026-06-01' AS target_date,        -- "hoje"; troque por CURRENT_DATE se preferir
        'FIDC NXFS'       AS holder_name,         -- nome exato da entidade holder
        '%FLAMEX%'        AS originator_pattern   -- originador das parcelas
)
SELECT
    p.id,
    h.name                    AS holder_name,
    s.name                    AS asset_name,
    s.type                    AS asset_type,
    s.metadata->>'originator' AS originator,
    s.metadata->>'cedente'    AS cedente,
    p.position_date,
    p.amount,
    p.available
FROM       public.positions  p
CROSS JOIN params            pr
JOIN       public.entities   h ON h.aux_id = p.holder_aux_id
JOIN       public.securities s ON s.aux_id = p.asset_aux_id
WHERE s.type = 'parcela_fgts'
  AND s.metadata->>'originator' ILIKE pr.originator_pattern
  AND h.name = pr.holder_name
  AND p.position_date = pr.target_date
  AND p.amount = 1
  AND p.available = 1
ORDER BY s.name;


-- ----------------------------------------------------------------------------
-- PASSO 1b — (opcional) transações que referenciam essas posições (checagem de FK)
-- ----------------------------------------------------------------------------
WITH params AS (
    SELECT
        DATE '2026-06-01' AS target_date,
        'FIDC NXFS'       AS holder_name,
        '%FLAMEX%'        AS originator_pattern
)
SELECT t.*
FROM public.transactions t
WHERE t.position_id IN (
    SELECT p.id
    FROM       public.positions  p
    CROSS JOIN params            pr
    JOIN       public.entities   h ON h.aux_id = p.holder_aux_id
    JOIN       public.securities s ON s.aux_id = p.asset_aux_id
    WHERE s.type = 'parcela_fgts'
      AND s.metadata->>'originator' ILIKE pr.originator_pattern
      AND h.name = pr.holder_name
      AND p.position_date = pr.target_date
      AND p.amount = 1
      AND p.available = 1
);


-- ----------------------------------------------------------------------------
-- PASSO 2 — DELETE (em transação; ROLLBACK por padrão = NÃO apaga).
--           Valide o RETURNING e, se estiver correto, troque ROLLBACK por COMMIT.
-- ----------------------------------------------------------------------------
BEGIN;

WITH params AS (
    SELECT
        DATE '2026-06-01' AS target_date,
        'FIDC NXFS'       AS holder_name,
        '%FLAMEX%'        AS originator_pattern
)
DELETE FROM public.positions p
USING params pr
WHERE p.asset_aux_id IN (
        SELECT aux_id FROM public.securities
        WHERE type = 'parcela_fgts'
          AND metadata->>'originator' ILIKE pr.originator_pattern
      )
  AND p.holder_aux_id IN (
        SELECT aux_id FROM public.entities WHERE name = pr.holder_name
      )
  AND p.position_date = pr.target_date
  AND p.amount = 1
  AND p.available = 1
RETURNING p.id, p.holder_aux_id, p.asset_aux_id, p.position_date, p.amount, p.available;

-- >>> Confira a contagem/linhas do RETURNING acima. <<<
ROLLBACK;   -- troque por COMMIT quando validado
-- COMMIT;
