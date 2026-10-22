
    
    



select production_standard_raw
from (select * from SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__job_operation where standard_format != 'HR') dbt_subquery
where production_standard_raw is null


