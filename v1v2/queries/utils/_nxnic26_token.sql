-- Metadados do token NXNIC26-1 (id 2374) no V2
SELECT
    tk.id,
    e.name,
    tk.issuance_price,
    tk.issuance_amount,
    tk.face_value,
    tk.maturity_date,
    tk.max_offering_date,
    tk.duration_months,
    tk.internal_rate_of_return,
    tk.return_percentage_cdi,
    tk.estimated_spread_over_cdi,
    tk.estimated_spread_over_inflation,
    idx.name AS indexer,
    tk.indexer_id,
    tk.issuer_id,
    tk.strategy_id,
    tk.structure_id
FROM tokens tk
JOIN entities e ON e.id = tk.id
LEFT JOIN indexers idx ON idx.id = tk.indexer_id
WHERE tk.id = 2374;
