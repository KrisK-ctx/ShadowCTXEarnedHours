

-- Silver/intermediate: per-unit standard hours for every Kinetic job operation (SD-14).
-- Reproduces Epicor's own ESTPRODHOURS formulas (documented on ERP_JOBOPER), inverted to a
-- PER-UNIT rate so it can be multiplied by QUANTITY PRODUCED (not planned quantity) --
-- that is the actual earned-hours definition. est_production_hours is retained as a
-- cross-check only (SD-11) -- it is the BUDGET figure, not earned hours.
--
-- basis_value: E=1, C=100, M=1000, T=10000 (STANDARD_BASIS applies only to HP/MP formats).
-- Codes OH/OM/CP are implemented even though not currently present in the data --
-- Kinetic is the permanent platform and should handle formats we don't yet see (same
-- principle production's own build follows).

with job_operation as (

    select *
    from SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__job_operation

),

basis as (

    select
        *,
        case standard_basis
            when 'E' then 1
            when 'C' then 100
            when 'M' then 1000
            when 'T' then 10000
            else null
        end as basis_value
    from job_operation

)

select
    company_code,
    job_num,
    assembly_seqnum,
    operation_seqnum,
    operation_code,
    run_quantity,
    standard_format,
    standard_basis,
    production_standard_raw,
    est_production_hours,                      -- cross-check only (SD-11), NOT earned hours

    case standard_format
        when 'HR' then production_standard_raw / nullif(run_quantity, 0)
        when 'PH' then 1 / nullif(production_standard_raw, 0)
        when 'PM' then 1 / nullif(production_standard_raw * 60, 0)
        when 'HP' then production_standard_raw / nullif(basis_value, 0)
        when 'MP' then production_standard_raw / nullif(basis_value * 60, 0)
        when 'OH' then 1 / nullif(ops_per_part * production_standard_raw, 0)
        when 'OM' then 1 / nullif(ops_per_part * production_standard_raw * 60, 0)
        when 'CH' then 1 / nullif(quantity_per_cycle * production_standard_raw, 0)
        when 'CP' then 1 / nullif(quantity_per_cycle * production_standard_raw * 60, 0)
        else null  -- unrecognized format: deliberately visible as NULL, not guessed
    end as std_hours_per_unit,

    is_subcontract,
    is_operation_complete,
    is_job_complete
from basis