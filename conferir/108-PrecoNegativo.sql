select * from entities where id in (1057331, 1057332)

-- 1057331	CR-FGTS-30-01-SENIOR
-- 1057332	NXFSE26-1

select *
from valuations
where asset_id in (1057331)
order by date desc, asset_id





