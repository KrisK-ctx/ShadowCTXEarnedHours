select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select job_num
from SANDBOX_EARNEDHOURS_SHADOW.SILVER.int_labor_standard_hours
where job_num is null



      
    ) dbt_internal_test