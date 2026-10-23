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
-- SD-19 (REVISED per SD-23 empirical re-investigation): operation_earned_hours is computed
-- from JobOper.QUANTITY_COMPLETED, NOT from summing LaborDtl.LaborQty across transactions.
-- The original justification for this (an extract-completeness theory, "missing
-- transactions") was WRONG and has been retracted (SD-20 retracted). The real root cause
-- of the original gap was a case-sensitivity bug in our own Bronze joins (job_num,
-- part_num, employee_num, etc. stored with inconsistent casing for the same real-world
-- key -- see stg_ctxepicorkinetic__labor_detail SD-22). After normalizing case
-- (upper(trim())) everywhere, transaction-summed quantity matches QUANTITY_COMPLETED
-- exactly for 99.3% of operations. The remaining ~0.7% (concentrated in a handful of very
-- high-volume jobs) are genuine non-labor-tracked completions -- QUANTITY_COMPLETED
-- incremented by a round "lot" amount with no corresponding per-unit labor transaction
-- (e.g. bulk receipt/backflush). QUANTITY_COMPLETED remains the more complete, authoritative
-- measure of what was actually completed, so the SD-19 decision itself (anchor on
-- QUANTITY_COMPLETED) is kept -- it was right, just for a different reason than originally
-- stated. int_labor_detail's transaction-summed earned_hours remains available as a
-- cross-check (SD-15/SD-19), now reconciling almost exactly after the case fix.
--
-- SD-24 (empirical finding, NOT YET IMPLEMENTED -- open): when production_standard_raw = 0
-- (pure setup-only operation), production's EARNED_HOURS_JOB_OPERATION sometimes allocates
-- a flat earned_hours credit equal to est_setup_hours. Tested as a blanket rule (flat credit
-- whenever production_standard_raw = 0) and that rule is NOT uniformly correct: it improved
-- CCR's match rate and was neutral for QTS, but made CDT's aggregate gap worse (-1.49% ->
-- +4.17%), because a material share of CDT's zero-standard operations do NOT get the
-- est_setup_hours credit in production (341 of ~1700 cases checked). Production's actual
-- rule for this case is more conditional than "flat credit whenever standard=0" and hasn't
-- been isolated yet. Reverted; est_setup_hours is carried through below for visibility/
-- future investigation, but does NOT feed operation_earned_hours. Flagged for discussion
-- rather than silently applied, since it is not proven at the company level.

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
    est_setup_hours,                   -- SD-24: carried for visibility only, not yet used
    est_production_hours,              -- cross-check only (SD-11), NOT earned hours
    std_hours_per_unit,
    std_hours_per_unit * quantity_completed    as operation_earned_hours,     -- SD-19/SD-24

    is_subcontract,
    is_operation_complete,
    is_job_complete
from rate
