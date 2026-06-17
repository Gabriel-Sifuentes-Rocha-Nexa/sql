-- V1: serie de pu (preco sujo) do token NXCOA27-10
SELECT v.valuation_date, v.type, v.value, v.metadata
FROM valuations v
WHERE v.aux_id='107922be-d2a1-497f-bd34-3e97dab9045c'
  AND v.valuation_date BETWEEN DATE '2026-06-10' AND DATE '2026-06-18'
ORDER BY v.valuation_date, v.type
