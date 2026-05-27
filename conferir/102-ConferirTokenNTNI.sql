
select * from tokens
where strategy_id=6

select * from token_strategies

select * from valuations where asset_id= 423--582
and last_valuation_flag


select * from positions where block_id =954


select * from tokens

select * from valuations where asset_id in (select id from ntnis)
-- and lot_id=1
and date::date='2025-02-17'
order by date desc

select * from valuations where asset_id = 762
and lot_id=1
order by date desc


select * from positions where asset_id=423
order by date


