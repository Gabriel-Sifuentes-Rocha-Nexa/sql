-- V2: token 2374 -> MOIC + NTN-I subjacente (via posicao TOKENIZATION) + face USD
SELECT
    e.name                AS token_name,
    tk.issuance_price,
    tk.estimated_moic,
    tk.internal_rate_of_return,
    tk.duration_months,
    tk.max_offering_date,
    tk.maturity_date      AS token_maturity,
    n.id                  AS ntni_id,
    nn.name               AS ntni_name,
    n.face_value_usd,
    n.maturity_date       AS ntni_maturity
FROM tokens tk
JOIN entities e        ON e.id = tk.id
LEFT JOIN positions pos             ON pos.financial_account_id IN (
        SELECT fa.id FROM financial_accounts fa
        WHERE fa.name = 'assets pledged as collateral - ' || e.name)
LEFT JOIN ntnis n      ON n.id = pos.asset_id
LEFT JOIN entities nn  ON nn.id = n.id
WHERE tk.id = 2374
LIMIT 5;
