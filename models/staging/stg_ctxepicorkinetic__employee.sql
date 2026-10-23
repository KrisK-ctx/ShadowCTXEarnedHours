{{
    config(
        unique_key=['company_code', 'emp_id']
    )
}}

-- Bronze: Kinetic employee master. Thin rename only. Gated by the enrollment view (SD-10).
-- jc_dept (JCDEPT) is the job-costing department -- the reporting one. The separate
-- DEPARTMENT column is free-text HR data and is deliberately not carried as the
-- reporting department (same column trap production documents).
--
-- SD-22: emp_id is normalized with upper(trim()) -- see
-- stg_ctxepicorkinetic__labor_detail for the empirical case-variance finding.

with source as (

    select
        company                 as company_code,
        upper(trim(empid))      as emp_id,
        name                    as full_name,
        firstname               as first_name,
        lastname                as last_name,
        upper(trim(jcdept))     as jc_dept,
        shift                   as shift_num,
        laborrate               as labor_rate,
        empstatus               as employee_status,
        productionworker        as is_production_worker,
        enrollmentdate          as enrollment_date_text,
        departuredate           as departure_date_text,
        sysrevid                as _sysrevid
    from {{ source('ctxepicorkinetic', 'ERP_EMPBASIC') }}

)

select source.*, current_timestamp() as _loaded_at
from source
inner join {{ ref('stg_ctxepicorkinetic__company_enrollment') }} as gate
    on source.company_code = gate.company_code
