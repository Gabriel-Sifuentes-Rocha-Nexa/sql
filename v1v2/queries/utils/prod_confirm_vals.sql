-- PROD confirm: as valuations alvo existem e sao as linhas certas?
SELECT a.name AS token, v.id, v.date::text AS date, v.clean_price::text AS clean,
       v.accrued_interest::text AS accr, v.cash_flow::text AS cf, v.last_valuation_flag AS vig
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE v.id IN (260143,260144,260145,260146,260147,260148,188248,
               196211,
               5956653,5956654,5961251,5961252)
ORDER BY a.name, v.date
