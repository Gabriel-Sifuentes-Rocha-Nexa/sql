-- Eventos de cash_flow em TOKENS no dia 2025-01-15: amort (clean_price cai) vs cupom (accrued zera, clean estavel)?
-- Mostra a linha de evento + a valuation imediatamente anterior do mesmo token (prev_*) p/ ver o movimento.
WITH ev AS (
  SELECT a.id AS asset_id, a.name AS token, v.date,
         v.clean_price, v.accrued_interest, v.cash_flow,
         m.name AS metodologia
  FROM valuations v
  JOIN entities a ON a.id = v.asset_id
  LEFT JOIN valuation_methodologies m ON m.id = v.methodology_id
  WHERE v.date::date = DATE '2025-01-15'
    AND v.cash_flow <> 0
    AND a.id IN (SELECT id FROM tokens)
)
SELECT ev.token, ev.metodologia, ev.date,
       prev.date         AS prev_date,
       prev.clean_price   AS prev_clean,
       ev.clean_price     AS clean,
       prev.accrued_interest AS prev_accr,
       ev.accrued_interest   AS accr,
       ev.cash_flow,
       CASE
         WHEN ev.clean_price < prev.clean_price - 0.0001 THEN 'AMORTIZACAO (clean caiu)'
         WHEN ev.clean_price <= 0.0001                    THEN 'RESGATE/VENCIMENTO (clean ~0)'
         WHEN ev.accrued_interest < prev.accrued_interest - 0.0001 THEN 'CUPOM (accrued zerou, clean estavel)'
         ELSE 'OUTRO'
       END AS classificacao
FROM ev
LEFT JOIN LATERAL (
  SELECT v2.date, v2.clean_price, v2.accrued_interest
  FROM valuations v2
  WHERE v2.asset_id = ev.asset_id AND v2.date < ev.date
  ORDER BY v2.date DESC
  LIMIT 1
) prev ON TRUE
ORDER BY ev.token, ev.date
