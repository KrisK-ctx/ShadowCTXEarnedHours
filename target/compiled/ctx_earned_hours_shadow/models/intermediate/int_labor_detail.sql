

-- Silver/intermediate: recomputed labor fact at the labor-transaction grain.
-- earned_hours is computed ONLY for direct (Production, non-rework) labor (SD-13) --
-- the reconciliation target (EARNED_HOURS_JOB_OPERATION) is itself "direct labor only",
-- and Epicor's own native rule treats rework as always-zero earned hours. Setup/Indirect
-- get earned_hours = 0 (a real zero, not an unknown) -- Setup's native formula is a
-- running-total calculation across an operation's setup transactions, not reproduced here
-- because it isn't needed for this reconciliation target.
--
-- earned_hours can be LEGITIMATELY NEGATIVE (reversal/correction labor transactions carry
-- negative quantity_produced -- confirmed against live data: all negative cases trace to
-- negative quantity_produced with a positive standard rate, never a negative rate) and
-- LEGITIMATELY NULL for Production rows whose operation standard is unresolved (no
-- matching ERP_JOBOPER row, or an unrecognized standard_format/zero denominator --
-- confirmed 1.2% of Production rows, flagged via has_unresolved_standard below rather
-- than silently defaulted to zero, per "flag bad data, don't silently fix it").
--
-- native_earned_hours_crosscheck (Epicor's own EARNEDHRS, carried from Bronze) is kept
-- for comparison only -- never treated as the reported figure (SD-11).
--
-- UPDATE (SD-19, reconciliation finding): this per-transaction earned_hours is now a
-- DIAGNOSTIC/cross-check column only -- Gold's fct_labor sources the authoritative
-- operation-level earned_hours from int_labor_standard_hours.operation_earned_hours
-- (JobOper.QUANTITY_COMPLETED), not by summing this column. Reconciliation against
-- production confirmed the summed-transaction approach under/over-counts: the current
-- MATILLION_RAW extract doesn't contain full labor history, and reversal transactions
-- introduce sign-flip noise, both of which QUANTITY_COMPLETED (Epicor's own running
-- total) is immune to. This column stays -- it's exactly what exposed the bug.

with labor as (

    select *
    from SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__labor_detail

),

standard_hours as (

    select *
    from SANDBOX_EARNEDHOURS_SHADOW.SILVER.int_labor_standard_hours

),

job_header as (

    select company_code, job_num, is_mrp_planning_job
    from SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__job_header

)

select
    labor.company_code,
    labor.job_num,
    labor.assembly_seqnum,
    labor.operation_seqnum,
    labor.labor_header_seqnum,
    labor.labor_detail_seqnum,
    labor.employee_num,
    labor.jc_dept,
    labor.resource_group_key,
    labor.labor_type_code,
    labor.labor_type_pseudo,
    labor.is_rework,
    labor.quantity_produced,
    labor.quantity_scrapped,
    labor.actual_hours,
    labor.burden_hours,
    labor.clock_in_date_text,
    labor.payroll_date_text,
    labor.fiscal_year,
    labor.fiscal_period,
    job_header.is_mrp_planning_job,

    standard_hours.std_hours_per_unit,
    standard_hours.standard_format,

    case
        when labor.labor_type_pseudo = 'P' and not labor.is_rework
            then labor.quantity_produced * standard_hours.std_hours_per_unit
        else 0
    end as earned_hours,

    (labor.labor_type_pseudo = 'P' and not labor.is_rework
        and standard_hours.std_hours_per_unit is null) as has_unresolved_standard,

    labor.native_earned_hours_crosscheck

from labor
left join standard_hours
    on  labor.company_code      = standard_hours.company_code
    and labor.job_num           = standard_hours.job_num
    and labor.assembly_seqnum   = standard_hours.assembly_seqnum
    and labor.operation_seqnum  = standard_hours.operation_seqnum
left join job_header
    on  labor.company_code = job_header.company_code
    and labor.job_num      = job_header.job_num