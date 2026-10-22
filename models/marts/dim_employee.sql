{{
    config(
        materialized='dynamic_table',
        target_lag='1 hour',
        snowflake_warehouse='COMPUTE_WH_CTX_SCIMDEFAULT',
        refresh_mode='INCREMENTAL'
    )
}}

-- Gold: conformed employee dimension, from Bronze.

select
    {{ generate_surrogate_key(['company_code', 'emp_id']) }} as employee_key,
    company_code,
    emp_id,
    full_name,
    first_name,
    last_name,
    jc_dept,
    shift_num,
    labor_rate,
    employee_status,
    is_production_worker,
    enrollment_date_text,
    departure_date_text
from {{ ref('stg_ctxepicorkinetic__employee') }}
