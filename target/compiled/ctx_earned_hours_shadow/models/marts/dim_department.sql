

-- Gold: conformed department dimension, from Bronze. Built for completeness/future
-- grains -- NOT joined into fct_labor below, since production's own
-- EARNED_HOURS_JOB_OPERATION grain doesn't carry department either (verified via its
-- column list: job/operation/part/resource, no department).

select
    md5(concat_ws('|',coalesce(cast(company_code as varchar), '_surrogate_key_null_'),coalesce(cast(jc_dept as varchar), '_surrogate_key_null_'))) as department_key,
    company_code,
    jc_dept,
    department_description,
    is_global_jc_dept
from SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__department