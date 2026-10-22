
    
    

select
    part_dim_key as unique_field,
    count(*) as n_records

from SANDBOX_EARNEDHOURS_SHADOW.GOLD.dim_part
where part_dim_key is not null
group by part_dim_key
having count(*) > 1


