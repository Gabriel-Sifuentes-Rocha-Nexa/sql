-- V2 PROD (:5003): posicoes vigentes do token NXCOA25-2 (asset 1685) e caixa BRL na
-- conta de colateral. Confirma token=0 e BRL retido apos o resgate de 01-21.
SELECT a.name AS ativo,
       fa.name AS conta,
       p.date,
       p.total_quantity,
       p.last_position_flag AS vig
FROM positions p
JOIN entities a ON a.id = p.asset_id
JOIN financial_accounts fa ON fa.id = p.financial_account_id
WHERE p.last_position_flag = TRUE
  AND ( (p.asset_id = 1685)
        OR (p.asset_id = 2 AND fa.name = 'assets pledged as collateral - NXCOA25-2') )
ORDER BY a.name, fa.name