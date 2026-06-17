-- V2: panorama da serie de valuations do asset 1412931
SELECT m.name AS meth, count(*) AS n, min(v.date)::text AS mind, max(v.date)::text AS maxd,
       count(*) FILTER (WHERE v.last_valuation_flag) AS n_vig,
       count(*) FILTER (WHERE v.cash_flow <> 0) AS n_cf
FROM valuations v LEFT JOIN valuation_methodologies m ON m.id=v.methodology_id
WHERE v.asset_id=1412931
GROUP BY m.name
ORDER BY m.name
