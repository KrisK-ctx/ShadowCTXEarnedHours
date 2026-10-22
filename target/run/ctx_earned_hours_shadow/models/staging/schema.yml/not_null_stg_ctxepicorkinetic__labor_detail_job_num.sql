select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select job_num
from SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__labor_detail
where job_num is null



      
    ) dbt_internal_test