-- Algum TOKEN amortizou no V2 em 2025-01-16?
-- Sinais de amortizacao no dia:
--   (P) positions com transaction_type = 'AMORTIZATION'
--   (V) valuations com cash_flow <> 0 (linha de evento, nao a daily)
-- Coluna asset_e_token marca se o ativo (asset) e' um token (asset_id em tokens).
WITH pos AS (
  SELECT 'POSITION'::text AS fonte,
         h.name  AS holder,
         a.name  AS ativo,
         (a.id IN (SELECT id FROM tokens)) AS asset_e_token,
         pp.date,
         pp.variation::text AS valor,
         tt.name AS detalhe
  FROM positions pp
  JOIN entities a  ON a.id = pp.asset_id
  JOIN entities h  ON h.id = pp.holder_id
  JOIN transaction_types tt ON tt.id = pp.transaction_type_id
  WHERE pp.date::date = DATE '2025-01-16'
    AND tt.name = 'AMORTIZATION'
),
val AS (
  SELECT 'VALUATION'::text AS fonte,
         NULL::text AS holder,
         a.name AS ativo,
         (a.id IN (SELECT id FROM tokens)) AS asset_e_token,
         v.date,
         v.cash_flow::text AS valor,
         ('clean='||v.clean_price::text||' accr='||v.accrued_interest::text) AS detalhe
  FROM valuations v
  JOIN entities a ON a.id = v.asset_id
  WHERE v.date::date = DATE '2025-01-16'
    AND v.cash_flow <> 0
)
SELECT * FROM pos
UNION ALL
SELECT * FROM val
ORDER BY asset_e_token DESC, fonte, ativo, date
