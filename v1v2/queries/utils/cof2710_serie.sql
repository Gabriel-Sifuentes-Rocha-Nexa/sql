-- V2: serie do token NXCOA27-10 (via conta de colateral, ISSUANCE = securitization_series)
SELECT pos.asset_id AS serie_id, se.name AS serie_name, ss.issuer_id, tt.name AS txn
FROM financial_accounts fa
JOIN positions pos ON pos.financial_account_id=fa.id
JOIN securitization_series ss ON ss.id=pos.asset_id
JOIN entities se ON se.id=ss.id
LEFT JOIN transaction_types tt ON tt.id=pos.transaction_type_id
WHERE fa.name='assets pledged as collateral - NXCOA27-10'
GROUP BY pos.asset_id, se.name, ss.issuer_id, tt.name
