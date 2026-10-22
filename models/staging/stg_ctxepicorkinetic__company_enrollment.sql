{{
    config(
        materialized='view'
    )
}}

-- Bronze: Kinetic company enrollment gate, reused directly, not rebuilt (SD-10).
-- Never hardcode a Kinetic company list anywhere downstream -- join to this model.

select
    company       as company_code,
    isactive      as is_active_raw,
    fiscalyear_start,
    fiscalperiod_start,
    fiscalyear_end,
    fiscalperiod_end
from {{ source('ctxepicorkinetic', 'CTXEPICORKINETIC_V_ANALYTICS_COMPANY_ENROLLMENT') }}
where isactive = 'Y'
