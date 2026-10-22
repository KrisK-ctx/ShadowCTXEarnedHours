{{
    config(
        unique_key=['company_code', 'jc_dept']
    )
}}

-- Bronze: Kinetic job-costing department master. Thin rename only.
-- Gated by the enrollment view (SD-10).

with source as (

    select
        company                 as company_code,
        jcdept                  as jc_dept,
        description             as department_description,
        globaljcdept            as is_global_jc_dept,
        sysrevid                as _sysrevid
    from {{ source('ctxepicorkinetic', 'ERP_JCDEPT') }}

)

select source.*, current_timestamp() as _loaded_at
from source
inner join {{ ref('stg_ctxepicorkinetic__company_enrollment') }} as gate
    on source.company_code = gate.company_code
