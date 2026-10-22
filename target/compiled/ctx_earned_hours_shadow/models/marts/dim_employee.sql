

-- Gold: conformed employee dimension, from Bronze.

select
    md5(concat_ws('|',coalesce(cast(company_code as varchar), '_surrogate_key_null_'),coalesce(cast(emp_id as varchar), '_surrogate_key_null_'))) as employee_key,
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
from SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__employee