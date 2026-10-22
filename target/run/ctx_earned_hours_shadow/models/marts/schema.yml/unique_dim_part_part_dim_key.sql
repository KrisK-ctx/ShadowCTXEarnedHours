select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    

select
    part_dim_key as unique_field,
    count(*) as n_records

from SANDBOX_EARNEDHOURS_SHADOW.GOLD.dim_part
where part_dim_key is not null
group by part_dim_key
having count(*) > 1



      
    ) dbt_internal_test