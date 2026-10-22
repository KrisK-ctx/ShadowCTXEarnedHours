select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select department_key
from SANDBOX_EARNEDHOURS_SHADOW.GOLD.dim_department
where department_key is null



      
    ) dbt_internal_test