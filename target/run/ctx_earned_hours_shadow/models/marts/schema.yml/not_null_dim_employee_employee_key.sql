select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select employee_key
from SANDBOX_EARNEDHOURS_SHADOW.GOLD.dim_employee
where employee_key is null



      
    ) dbt_internal_test