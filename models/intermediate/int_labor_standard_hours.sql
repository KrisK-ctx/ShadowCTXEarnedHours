{{
    config(
        materialized='dynamic_table',
        target_lag='1 hour',
        snowflake_warehouse='COMPUTE_WH_CTX_SCIMDEFAULT',
        refresh_mode='INCREMENTAL'
    )
}}

-- Silver/intermediate: per-unit standard hours for every Kinetic job operation (SD-14).
-- Reproduces Epicor's own ESTPRODHOURS formulas (documented on ERP_JOBOPER), inverted to a
-- PER-UNIT rate. est_production_hours is retained as a cross-check only (SD-11) -- it is
-- the BUDGET figure, not earned hours.
--
-- basis_value: E=1, C=100, M=1000, T=10000 (STANDARD_BASIS applies only to HP/MP formats).
-- Codes OH/OM/CP are implemented even though not currently present in the data -- Kinetic
-- is the permanent platform and should handle formats we don't yet see (same principle
-- production's own build follows).
--
-- SD-19 (reconciliation finding): operation_earned_hours is computed from
-- JobOper.QUANTITY_COMPLETED, NOT from summing LaborDtl.LaborQty across transactions.
-- Confirmed via reconciliation against production on 3 independent CDT examples (all
-- exact matches both directions): our transaction-summed quantity is vulnerable to (a)
-- the current MATILLION_RAW extract not containing full labor history (QTYCOMPLETED is
-- Epicor's own authoritative running total, unaffected by extract completeness) and (b)
-- sign-flip noise from reversal/correction transactions. QUANTITY_COMPLETED is already
-- scoped to Production/non-rework by Epicor's own field definition, consistent with SD-13.

with job_operation as (

    select *
    from {{ ref('stg_ctxepicorkinetic__job_operation') }}

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

),

rate as (

    select
        *,
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
        end as std_hours_per_unit
    from basis

)

select
    company_code,
    job_num,
    assembly_seqnum,
    operation_seqnum,
    operation_code,
    run_quantity,
    quantity_completed,
    standard_format,
    standard_basis,
    production_standard_raw,
    est_production_hours,              -- cross-check only (SD-11), NOT earned hours
    std_hours_per_unit,
    std_hours_per_unit * quantity_completed    as operation_earned_hours,     -- SD-19

    is_subcontract,
    is_operation_complete,
    is_job_complete
from rate
