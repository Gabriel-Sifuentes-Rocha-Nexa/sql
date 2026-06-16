-- NXCOB26-4 (token) no V1: parâmetros de yield + composição (subjacente)
SELECT
    s.full_name,
    s.metadata->>'strategy'                       AS strategy,
    s.metadata->>'tokenYieldType'                 AS yield_type,
    s.metadata->>'tokenYieldRate'                 AS yield_rate,
    s.metadata->>'issuancePrice'                  AS issuance_price,
    s.metadata->>'issuanceAmount'                 AS issuance_amount,
    s.metadata->>'returnYieldEstimated'           AS tir_estimada,
    s.metadata->>'token_adjusted_price'           AS adj_price,
    s.metadata->>'maturity'                       AS maturity,
    s.metadata->>'maturityDate'                   AS maturity_date,
    s.metadata->>'emissionDate'                   AS emission_date,
    jsonb_array_length(COALESCE(s.metadata->'composition','[]'::jsonb)) AS n_underlyings,
    s.metadata->'composition'                     AS composition
FROM securities s
WHERE s.full_name = 'NXCOB26-4';
