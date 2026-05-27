-- Timezone
SET TIME ZONE 'America/Sao_Paulo';

-- Quem é o owner da tabela?
SELECT schemaname, tablename, tableowner 
FROM pg_tables 
WHERE tablename = 'holidays';

-- Quais currencies existem?
SELECT entities.id, entities.name from currencies
join entities on currencies.id=entities.id;

-- Quais são todas as entidades?
select * from entities;

-- Existe dados de curvas duplicados?
select * from curves
where date='2026-02-11'
and curve_id in (select id from entities where name='CURVA_DI_PRE_B3')
and parameter='7'

-- Quais são os paramettros das curvas?
select * from parameter_types

-- Quais financial accounts existem?
select * from financial_accounts

select * from consortiums

select * from entities

select * from valuations


select * from entities

select * from valuations where asset_id=24 and lot_id=1 order by "date";




select * FROM valuations where asset_id=29 and lot_id=2 order by "date" limit 1000


select * from valuations where asset_id=32 and lot_id=1 order by "date" limit 1000


select * from positions where transaction_type_id=13

select * from entities

