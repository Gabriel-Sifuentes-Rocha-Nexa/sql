-- valuations das cotas subjacentes em torno de 06-02/06-03
-- 1892 = ANCORA (NXCOF25-3, redime 06-03) ; 1906 = CANOPUS (NXCOF25-3, redime 06-02) ; 1891 = ANCORA (NXCOE25-2, redime 06-03)
SELECT a.name AS cota, v.id, v.date, m.name AS meth, v.clean_price, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v JOIN entities a ON a.id = v.asset_id
LEFT JOIN valuation_methodologies m ON m.id = v.methodology_id
WHERE v.asset_id IN (1892,1906,1891) AND v.date::date BETWEEN DATE '2025-06-01' AND DATE '2025-06-04'
ORDER BY a.name, v.date, v.id
