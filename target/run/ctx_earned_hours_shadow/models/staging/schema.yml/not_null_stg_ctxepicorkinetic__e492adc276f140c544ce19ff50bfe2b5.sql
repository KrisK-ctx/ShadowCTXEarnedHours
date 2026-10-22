select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select production_standard_raw
from (select * from SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__job_operation where standard_format != 'HR') dbt_subquery
where production_standard_raw is null



      
    ) dbt_internal_test