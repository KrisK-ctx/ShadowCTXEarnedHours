

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
-- SD-24 (REVISED -- isolated and implemented): when production_standard_raw = 0 (pure
-- setup-only operation), production's EARNED_HOURS_JOB_OPERATION credits a flat
-- est_setup_hours earned-hours value ONLY when actual setup labor was actually posted
-- (ERP_JOBOPER.actsetuphours > 0) for that operation -- otherwise it credits 0, even
-- though est_setup_hours itself is non-zero. The earlier blanket rule ("credit whenever
-- standard = 0") ignored this condition and was wrong for a material share of CDT.
-- This conditional rule was isolated empirically: among non-trivial cases
-- (est_setup_hours > 0), 88% of credited CDT operations had act_setup_hours > 0 vs. only
-- 7% of non-credited ones. Applied as a full rule and validated against the ENTIRE
-- zero-standard population across all 3 companies: CDT 96.18% match, QTS 100.00% match,
-- CCR 98.52% match -- a cross-company-validated rule, not a CDT-only fit.

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
    est_setup_hours,
    act_setup_hours,                   -- SD-24: drives the zero-standard credit condition
    est_production_hours,              -- cross-check only (SD-11), NOT earned hours
    std_hours_per_unit,
    case
        when production_standard_raw = 0 or production_standard_raw is null
            then case when act_setup_hours > 0 then est_setup_hours else 0 end  -- SD-24
        else std_hours_per_unit * quantity_completed                            -- SD-19
    end as operation_earned_hours,

    is_subcontract,
    is_operation_complete,
    is_job_complete
from rate