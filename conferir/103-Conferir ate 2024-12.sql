



select name, * from tokens
join entities on entities.id = tokens.id
order by 1



select * from valuations where asset_id =1036
order by date

select * from positions where block_id=743


select * from valuations where asset_id=663 and date::date='2024-11-08'


select * from positions where financial_account_id in (
    select id from financial_accounts where parent_id=2 and name='assets pledged as collateral - NXCOE26-3'
)

select * from entities 
join consortiums on entities.id=consortiums.id
where consortiums.id in (663,694,697)


select * from valuations where asset_id in (663) order by date limit 2;