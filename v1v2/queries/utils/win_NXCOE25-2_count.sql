-- NXCOE25-2 (3032): quantas valuations depois de 06-02? range? + rows 06-01..06-05
SELECT 'resumo' AS k, count(*)::text AS vals_apos_0602, min(v.date)::text AS mind, max(v.date)::text AS maxd, ''::text AS extra
FROM valuations v WHERE v.asset_id = 3032 AND v.date::date > DATE '2025-06-02'
UNION ALL
SELECT 'row', v.id::text, v.date::text, v.clean_price::text, v.cash_flow::text
FROM valuations v WHERE v.asset_id = 3032 AND v.date::date BETWEEN DATE '2025-06-01' AND DATE '2025-06-05'
ORDER BY 1, 3
