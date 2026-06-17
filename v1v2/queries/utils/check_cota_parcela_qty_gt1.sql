-- ============================================================
-- check_cota_parcela_qty_gt1
-- Objetivo: achar cotas de consórcio ou parcelas de FGTS cujo
--           total_quantity em positions ultrapassa |1|.
--
-- Estratégia (eficiente):
--   1) filtrar positions por ABS(total_quantity) > 1  -> corta os ~16M cedo;
--   2) agrupar por asset_id (conjunto pequeno de ativos anômalos);
--   3) só então classificar cada ativo em consórcio / FGTS.
--
-- Para uma cota/parcela única, a posição esperada é no máximo 1 unidade,
-- então qualquer linha com |total_quantity| > 1 é anomalia.
--
-- Notas de schema (v2):
--   - positions.asset_id -> entities.id
--   - consortiums.id = entities.id (cada linha = 1 cota)
--   - fgts.id        = entities.id (cada linha = 1 parcela)
--   - total_quantity e last_position_flag são mantidos por trigger.
-- ------------------------------------------------------------
WITH flagged AS (
    SELECT
        asset_id,
        MAX(ABS(total_quantity))                       AS max_abs_total_quantity,
        COUNT(*)                                       AS n_rows_gt1,
        COUNT(*) FILTER (WHERE last_position_flag)     AS n_current_rows_gt1
    FROM positions
    WHERE ABS(total_quantity) > 1
    GROUP BY asset_id
)
SELECT
    CASE WHEN c.id IS NOT NULL THEN 'consortium'
         WHEN g.id IS NOT NULL THEN 'fgts'
    END                                AS asset_class,
    f.asset_id,
    e.name                             AS asset_name,
    f.max_abs_total_quantity,
    f.n_rows_gt1,
    f.n_current_rows_gt1
FROM flagged f
LEFT JOIN consortiums c ON c.id = f.asset_id
LEFT JOIN fgts        g ON g.id = f.asset_id
JOIN      entities    e ON e.id = f.asset_id
WHERE c.id IS NOT NULL      -- é cota de consórcio
   OR g.id IS NOT NULL      -- é parcela de FGTS
ORDER BY asset_class, f.max_abs_total_quantity DESC;
