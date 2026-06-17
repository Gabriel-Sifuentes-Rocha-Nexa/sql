-- V1: transacoes envolvendo o token NXCOF25-3 (aux 285e81f8...) em torno de 06-02/06-03
SELECT t.transaction_date, t.type, t.price, t.amount,
       t.from_aux_id, t.to_aux_id, t.asset_aux_id, t.metadata
FROM transactions t
WHERE (t.asset_aux_id = '285e81f8-4114-4f5b-9749-38ddb5f093b8'
       OR t.from_aux_id = '285e81f8-4114-4f5b-9749-38ddb5f093b8'
       OR t.to_aux_id = '285e81f8-4114-4f5b-9749-38ddb5f093b8')
  AND t.transaction_date BETWEEN DATE '2025-05-29' AND DATE '2025-06-06'
ORDER BY t.transaction_date, t.id
