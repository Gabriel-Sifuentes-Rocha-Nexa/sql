-- ============================================================
-- investiga_cota_117051
-- Drill-down COMPLETO do histórico de positions da cota
--   asset_id = 117051  (COTA-CONSORCIO-CANOPUS-8400-1756-1345962)
-- que atingiu |total_quantity| = 2 (esperado: <= 1).
--
-- Mostra a linha do tempo inteira: de onde saiu, pra onde foi, quando.
--   date            -> data do evento da posição
--   created_at      -> quando a linha foi GRAVADA no banco (detecta re-ingestão)
--   variation       -> delta da posição naquele evento
--   total_quantity  -> saldo acumulado (por holder/lot/conta) após o evento
--   last_position_flag -> se é a posição corrente daquele (holder/asset/lot/conta)
-- ------------------------------------------------------------
SELECT
    p.id                                AS position_id,
    p.date,
    p.created_at,
    p.updated_at,
    p.trade_date,
    tt.name                             AS transaction_type,
    p.variation,
    p.total_quantity,
    p.last_position_flag                AS last_flag,
    p.event_code,
    p.payment_code,
    p.lot_id,
    p.block_id,
    p.financial_account_id,
    fa.name                             AS financial_account,
    p.holder_id,
    h.name                              AS holder_name,
    p.originator_id,
    o.name                              AS originator_name,
    p.broker_id,
    p.transaction_unit_price
FROM positions p
LEFT JOIN transaction_types  tt ON tt.id = p.transaction_type_id
LEFT JOIN financial_accounts fa ON fa.id = p.financial_account_id
LEFT JOIN entities           h  ON h.id  = p.holder_id
LEFT JOIN entities           o  ON o.id  = p.originator_id
WHERE p.asset_id = 117051
ORDER BY p.date, p.created_at, p.id;
