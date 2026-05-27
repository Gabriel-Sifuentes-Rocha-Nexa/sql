select * from entities where id=2

select * from entities

select * from positions where block_id in (
select block_id from positions where asset_id=186)

select * from financial_accounts where id in (10,11)

select * from transaction_types where id=11

select * from valuations 
where asset_id=186 and lot_id=0
order by "date" desc 

select * from entities where "name"='USD'

select * from valuation_methodologies

select * from exchange_rates where numerator_id=1 and denominator_id=2 and methodology_id=6
and date>'2025-01-09'
order by date

select * from valuations where asset_id=762 order by date


select * from tokens

select * from ntnis

select * from positions where asset_id=423

select * from exchange_rates where numerator_id=1 and denominator_id=2
and date::date='2025-02-14';

select ntnis.id, ntnis.face_value_usd, ntnis.maturity_date,
    valuations.date, valuations.lot_id, valuations.methodology_id,
    valuations.clean_price, valuations.accrued_interest,
    valuations.indexer_percentage, valuations.spread_over_indexer,
    valuations.spread_over_cdi, valuations.spread_over_inflation,
    valuations.last_valuation_flag
from ntnis 
join valuations on ntnis.id = valuations.asset_id
where maturity_date='2026-03-16'
and valuations.methodology_id=2


select ntnis.id, ntnis.face_value_usd, ntnis.maturity_date,
    positions.*
from ntnis 
join positions on ntnis.id = positions.asset_id
where maturity_date='2026-03-16'

select * from positions where block_id in (1902, 1904)
order by date

select * from valuations where asset_id=423
and methodology_id=2
and lot_id=1
order by date

select * from valuations where asset_id=423
and methodology_id=2
and lot_id=1
order by date

select * from positions where block_id in (
select distinct block_id from positions where asset_id=423)
order by date

select * from positions where block_id in (
select distinct block_id from positions where asset_id=762)
order by date


select * from ntnis

ALTER ROLE gabriel_sifuentes SET timezone TO 'America/Sao_Paulo';

select * from transaction_types where id in (1, 13);

select * from positions where block_id in (
select block_id from positions where asset_id=2373)
order by date

select * from ntnis

select * from entities order by created_at desc


select * from valuations where asset_id=2373 and lot_id=2 order by date, lot_id, methodology_id;

select * from valuations where asset_id in (select id from ntnis) order by asset_id

select * from positions where block_id in (
select block_id from positions where asset_id in (2373))

select * from entities where id in (3024,
3025,
3026,
3027)

select * from valuations order by created_at desc

select * from positions ORDER BY created_at desc

select * from entities where id=3031



SELECT DISTINCT ON (CAST(valuations.date AS DATE)) 
    CAST(valuations.date AS DATE) AS date, 
    entities.name AS token_ticker, 
    entities.id AS token_id, 
    tokens.issuance_amount * (valuations.clean_price + COALESCE(valuations.accrued_interest, 0)) AS volume 
FROM tokens
JOIN entities ON entities.id = tokens.id
JOIN valuations ON valuations.asset_id = entities.id
WHERE entities.name = 'NXCDBD25-1'
and methodology_id=2
ORDER BY CAST(valuations.date AS DATE), valuations.date DESC;

select * from valuations where asset_id=32 order by date desc

select * from valuations where asset_id=29 order by date desc

select * from positions where block_id=7

select * from entities where name='NXCOD26-1'

select* from tokens where id =1569 



SELECT DISTINCT ON (CAST(valuations.date AS DATE)) 
    CAST(valuations.date AS DATE) AS data, 
    entities.name AS token_ticker, 
    entities.id AS token_id, 
    tokens.issuance_amount * (valuations.clean_price + COALESCE(valuations.accrued_interest, 0)) AS volume,
    tokens.issuance_amount as quantidade_emitida,
    token_strategies.strategy_name,
    token_structures.structure_name
FROM tokens
JOIN entities ON entities.id = tokens.id
JOIN valuations ON valuations.asset_id = entities.id
join token_strategies on token_strategies.id = tokens.strategy_id
join token_structures on token_structures.id = tokens.structure_id
WHERE entities.name like 'NXNIB25-1'
and methodology_id=2
ORDER BY CAST(valuations.date AS DATE), valuations.date DESC;





SELECT 
    entities.name AS nome_entidade, 
    positions.holder_id AS id_entidade, 
    CAST(positions.date AS DATE) AS data,
    round(total_quantity,2) as quantidade,
    left(ntnis.maturity_date::text, 7) vencimento_ntni
FROM positions
JOIN entities ON positions.holder_id = entities.id
join ntnis on positions.asset_id=ntnis.id
WHERE 1=1
  AND positions.financial_account_id = 11
  AND positions.asset_id IN (SELECT id FROM ntnis)
ORDER BY 
    data DESC, 
    nome_entidade;



select * from ntnis
3031	2035-01-15	2.805555

select * from valuations where asset_id=3031
and methodology_id=2 and lot_id=2
order by date limit 1

select * from entities where name like 'NXNIA35-1'

select * from valuations where asset_id=3083
order by date limit 1


-- Get PTAX
select * from exchange_rates
where date::date < '2026-03-10'
and numerator_id in (select id from entities where name = 'USD')
and denominator_id in (select id from entities where name = 'BRL')
order by date desc 
limit 1

select * from valuation_methodologies where id=6

select valuations.asset_id as id_ativo, 'NTN-I 891300/2035-01-15' as nome_ativo, valuations.date as data, valuations.clean_price+coalesce(valuations.accrued_interest, 0) as preco from valuations 
where asset_id in (select ntnis.id from ntnis where maturity_date::text like '2035-01-1_')
and lot_id =1
and methodology_id=2
order by date
