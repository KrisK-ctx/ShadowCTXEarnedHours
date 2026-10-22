{{
    config(
        materialized='dynamic_table',
        target_lag='1 hour',
        snowflake_warehouse='COMPUTE_WH_CTX_SCIMDEFAULT',
        refresh_mode='INCREMENTAL'
    )
}}

-- Gold: conformed department dimension, from Bronze. Built for completeness/future
-- grains -- NOT joined into fct_labor below, since production's own
-- EARNED_HOURS_JOB_OPERATION grain doesn't carry department either (verified via its
-- column list: job/operation/part/resource, no department).

select
    {{ generate_surrogate_key(['company_code', 'jc_dept']) }} as department_key,
    company_code,
    jc_dept,
    department_description,
    is_global_jc_dept
from {{ ref('stg_ctxepicorkinetic__department') }}
