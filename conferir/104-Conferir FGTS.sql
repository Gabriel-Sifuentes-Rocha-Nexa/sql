-- Deletando tudo de FGTS
select * from valuations where asset_id in (select id from fgts);
select * from positions where block_id in(
    select block_id from positions where asset_id in (select id from fgts));
select * from entity_types where entity_id in (select id from fgts);
select * from fgts;
select * from entities where reference_table_id=3;

-- Procurando inconsistências
select * from FGTS 
where 1!=1 or
acquisition_value>face_value or
face_value_original!=face_value or
maturity_date=maturity_date_original or
spread_over_cdi < 0.01 or
spread_over_cdi > 0.05 or
spread_over_indexer > 0.19 or
spread_over_indexer < 0.13 or
1!=1
;

-- Procurando status que são é igual a ativa
select * from FGTS 
where status_id != 4
-- 1	cessao
-- 2	pre_aprovada
-- 3	aprovada
-- 4	ativa
-- 5	baixada


select * from tokens where strategy_id=5

select * from fgts where id = 2156

select * from entities where id = 2156

select asset_id as id_ativo, 'fgts' as nome_ativo, date as data, clean_price + accrued_interest as preco from valuations 
where 1=1
and asset_id=2156
and lot_id=1 
and methodology_id=8

select * from ntnis

select * from positions where asset_id='3097'


select * from positions where asset_id in (
select id from entities where id in (select id from fgts)
and name like '%69878105%' limit 100000)
order by date


-- Posições criadas pelo assignment (asset = parcelas_fgts, holder = CR)
SELECT
e_holder.name AS cr_name,
COUNT(*) AS n_parcelas,
SUM(p.variation) AS total_variation,
MIN(p.date::date) AS data_cessao
FROM positions p
INNER JOIN entities e_holder ON e_holder.id = p.holder_id
INNER JOIN fgts f ON f.id = p.asset_id
WHERE e_holder.name IN ('CR-FGTS-12', 'CR-FGTS-15')
GROUP BY 1
ORDER BY 1;



select count(*) from positions 
where holder_id=15
and date::date='2025-10-31'
and asset_id in (select id from fgts)
and asset_id <> 2




select * from entities where name like '%68942895%'

select * from fgts where id =645850

select * from positions where asset_id=645850

select distinct originator_id from fgts where id in (
    645850,645851,645852,645853,645854,645855,645856,645857,645858,645859,645860,786018,786019,786020,786021,786022,786023,786024,786025,786026,786027,825264,825265,825266,825267,825268,825269,825270,825271,825272,825273
)




select * from positions
where holder_id=15
and asset_id in (select id from fgts)
and date::date='2025-10-30'
-- and financial_account_id=11
-- and variation=1
and asset_id=825281





select * from positions
where holder_id=15
and asset_id in (select id from fgts)
and date::date='2025-01-24'
and financial_account_id=11
and variation=1









with contas_permitidas as (
    select 11 as id
    union
    select fa.id
    from financial_accounts fa
    where fa.name ilike '%reservation-%'
),
posicoes_filtradas as (
    select
        p.date,
        p.date::date as data_inicio,
        lead(p.date::date) over (
            partition by
                p.holder_id,
                p.asset_id,
                p.financial_account_id
            order by
                p.date
        ) as proxima_data,
        p.holder_id,
        p.asset_id,
        p.financial_account_id,
        p.total_quantity
    from positions p
    join contas_permitidas cp
        on cp.id = p.financial_account_id
),
datas as (
    select distinct p.date::date as data
    from positions p
)
select
    d.data,
    pf.holder_id,
    sum(pf.total_quantity) as quantidade_total
from datas d
join posicoes_filtradas pf
    on d.data >= pf.data_inicio
   and (
        pf.proxima_data is null
        or d.data < pf.proxima_data
   )
group by
    d.data,
    pf.holder_id
order by
    d.data,
    pf.holder_id;





with contas_permitidas as (
    select 11 as id
    union
    select fa.id
    from financial_accounts fa
    where fa.name ilike '%reservation-%'
),
ultimas_posicoes_do_dia as (
    select *
    from (
        select
            p.date::date as data,
            p.holder_id,
            p.asset_id,
            p.financial_account_id,
            p.total_quantity,
            row_number() over (
                partition by
                    p.date::date,
                    p.holder_id,
                    p.asset_id,
                    p.financial_account_id
                order by p.date desc
            ) as rn
        from positions p
        join contas_permitidas cp
            on cp.id = p.financial_account_id
        join fgts f
            on f.id = p.asset_id
    ) x
    where rn = 1
)
select
    data,
    holder_id,
    sum(total_quantity) as quantidade_total
from ultimas_posicoes_do_dia
group by
    data,
    holder_id
order by
    data,
    holder_id;


select * from financial_accounts




select * 
from positions 
where asset_id=1019558
order by date



select * from entities where name like '%85768792%'

select * from positions where asset_id='1162509'



select name from entities where id in (
select asset_id from positions where asset_id in (
select id from entities where reference_table_id=3
and id not in (select id from fgts))
and date::date='2026-03-06'

)



select distinct date::date, count(*) from positions where asset_id in (
select id from entities where reference_table_id=3
and id not in (select id from fgts))
group by date::date


select name from entities where id in (
select asset_id from positions where asset_id in (
select id from entities where reference_table_id=3
and id not in (select id from fgts))
and date::date='2026-03-13')


select distinct assignor_id from fgts

select distinct obligor_person_type from fgts


select * from fgts where id=1240692


select DISTINCT cession_id from fgts


select * from fgts

select count(*) from positions 
where 1=1
-- and date::date='2026-03-06'
and asset_id in (select id from entities where reference_table_id=3)
and asset_id not in (select id from fgts)


select * from fgts where id='1057327'





select * from entities where name like '88839151002%'