

-- Bronze: Kinetic employee master. Thin rename only. Gated by the enrollment view (SD-10).
-- jc_dept (JCDEPT) is the job-costing department -- the reporting one. The separate
-- DEPARTMENT column is free-text HR data and is deliberately not carried as the
-- reporting department (same column trap production documents).

with source as (

    select
        company                 as company_code,
        empid                   as emp_id,
        name                    as full_name,
        firstname               as first_name,
        lastname                as last_name,
        jcdept                  as jc_dept,
        shift                   as shift_num,
        laborrate               as labor_rate,
        empstatus               as employee_status,
        productionworker        as is_production_worker,
        enrollmentdate          as enrollment_date_text,
        departuredate           as departure_date_text,
        sysrevid                as _sysrevid
    from MATILLION_RAW.CRETEX_EPICOR_KINETIC.ERP_EMPBASIC

)

select source.*, current_timestamp() as _loaded_at
from source
inner join SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__company_enrollment as gate
    on source.company_code = gate.company_code