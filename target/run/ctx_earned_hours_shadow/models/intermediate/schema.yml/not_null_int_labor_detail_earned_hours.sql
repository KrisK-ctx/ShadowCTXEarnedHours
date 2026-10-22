select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select earned_hours
from SANDBOX_EARNEDHOURS_SHADOW.SILVER.int_labor_detail
where earned_hours is null



      
    ) dbt_internal_test