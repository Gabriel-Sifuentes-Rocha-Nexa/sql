-- V1: serie de pu do token NXCOF25-3 (resumo + ultimos dias) e posicoes
SELECT 'pu_resumo' AS k, count(*)::text AS a, min(valuation_date)::text AS b, max(valuation_date)::text AS c
FROM valuations WHERE aux_id='285e81f8-4114-4f5b-9749-38ddb5f093b8' AND type='pu'
