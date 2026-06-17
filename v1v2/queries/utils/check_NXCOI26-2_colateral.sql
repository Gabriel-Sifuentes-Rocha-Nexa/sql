-- V2 PROD: o que esta na conta de colateral do NXCOI26-2?
-- TOKENIZATION = cota/parcela direto (token assets); ISSUANCE = serie (token de CR).
SELECT a.name AS subjacente,
       tt.name AS transaction_type,
       count(*) AS linhas,
       min(p.date) AS primeira,
       max(p.date) AS ultima
FROM positions p
JOIN entities a            ON a.id = p.asset_id
JOIN transaction_types tt  ON tt.id = p.transaction_type_id
JOIN financial_accounts fa ON fa.id = p.financial_account_id
WHERE fa.name = 'assets pledged as collateral - NXCOI26-2'
GROUP BY a.name, tt.name
ORDER BY a.name, tt.name
