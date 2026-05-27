select * from consortiums
where code = '00375cc8-e436-4122-a197-ce6b651df1b8'


--V-3a9e996d-05eb-40f5-afe2-10c95984400f

select * from valuations 
where asset_id=1482
and lot_id =1
order by date

select * from entities where id=1482



SELECT
    c.id,
    cs.name                             AS type,
    c.maturity_date_original            AS data_vencimento,
    st.name                             AS status,
    c.face_value                        AS valor_a_receber,
    e_trustee.name                      AS nome_administradora,
    c.wallet_fidc::text                 AS carteira_fidc,
    e_assignee.name                     AS veiculo_ativo,
    c.assignor                          AS cedente_ativo,
    c.created_at
FROM consortiums                c
JOIN entities       e_assignee  ON e_assignee.id  = c.assignee_id
JOIN contact_infos  ci_assignee ON ci_assignee.id = c.assignee_id
JOIN entities       e_trustee   ON e_trustee.id   = c.trustee_id
JOIN statuses       st          ON st.id           = c.status_id
JOIN consortium_strategies cs   ON cs.id           = c.strategy_id
WHERE st.name = 'ativa'
  AND cs.name IN (
      'cancelada', 'contemplada', 'contemplacao',
      'contemplacao_contemplada', 'contemplada_quitada',
      'contemplacao_contemplada_quitada'
  )
  AND ci_assignee.document    = '56125110000134'