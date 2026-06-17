-- NXCOF25-2: grupos de positions (token + conta colateral) com !=1 vigente (anomalia de last_position_flag)
SELECT h.name AS holder, a.name AS asset, p.lot_id, fa.name AS conta,
       count(*) AS total, count(*) FILTER (WHERE p.last_position_flag) AS n_vig
FROM positions p
JOIN entities h ON h.id=p.holder_id
JOIN entities a ON a.id=p.asset_id
JOIN financial_accounts fa ON fa.id=p.financial_account_id
WHERE p.asset_id=1938
   OR p.financial_account_id=(SELECT id FROM financial_accounts WHERE name='assets pledged as collateral - NXCOF25-2')
GROUP BY h.name, a.name, p.lot_id, fa.name
ORDER BY n_vig DESC, asset
