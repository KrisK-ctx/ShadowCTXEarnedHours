select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select part_dim_key
from SANDBOX_EARNEDHOURS_SHADOW.GOLD.dim_part
where part_dim_key is null



      
    ) dbt_internal_test