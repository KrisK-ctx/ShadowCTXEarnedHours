{{
    config(
        materialized='dynamic_table',
        target_lag='1 hour',
        snowflake_warehouse='COMPUTE_WH_CTX_SCIMDEFAULT',
        refresh_mode='INCREMENTAL'
    )
}}

-- Silver/intermediate: recomputed labor fact at the labor-transaction grain.
--
-- SD-26 (REVISED FOUNDATION): earned_hours is now computed for BOTH Production and Setup
-- direct labor, per the corrected business rule (see int_labor_standard_hours header) --
-- NOT just Production as SD-13 assumed. Indirect/Move still earn 0 (a real zero, no
-- standard applies to them, matching production's own IS_DIRECT_LABOR definition).
-- Rework still earns 0 at this grain (SD-13's rework exclusion is unaffected by SD-26).
--
-- Production (labor_type_pseudo='P', non-rework): earned_hours = quantity_produced *
-- production_std_hours_per_unit, computed per transaction (transaction grain is correct
-- -- confirmed directly against production's own SILVER.FACT_LABOR, which is itself a
-- transaction-grain rollup, not an operation-level QUANTITY_COMPLETED-driven calculation
-- as SD-19/23 assumed).
--
-- Setup (labor_type_pseudo='S', non-rework): earned_hours is NOT computed per transaction
-- here -- it is a FIXED, OPERATION-level amount (setup_earned_hours_credit, from
-- int_labor_standard_hours) that must be credited exactly ONCE per operation regardless of
-- how many Setup labor transactions exist on it. Carrying the per-operation credit through
-- on every Setup row here (rather than summing it per-transaction) would double/multiply
-- count it when this table is later aggregated -- exactly the historical defect this rule
-- corrects for (see int_labor_standard_hours header, job 200013 op 21). fct_labor is
-- responsible for adding this credit in ONCE per operation (e.g. via MAX(), not SUM()),
-- not by summing this column across Setup rows.
--
-- earned_hours can be LEGITIMATELY NEGATIVE (reversal/correction labor transactions carry
-- negative quantity_produced -- confirmed against live data: all negative cases trace to
-- negative quantity_produced with a positive standard rate, never a negative rate) and
-- LEGITIMATELY NULL for Production rows whose operation standard is unresolved (no
-- matching ERP_JOBOPER row, or a zero run_quantity denominator -- flagged via
-- has_unresolved_standard below rather than silently defaulted to zero, per "flag bad
-- data, don't silently fix it").
--
-- native_earned_hours_crosscheck (Epicor's own EARNEDHRS, carried from Bronze) is kept
-- for comparison only -- never treated as the reported figure (SD-11).

with labor as (

    select *
    from {{ ref('stg_ctxepicorkinetic__labor_detail') }}

),

standard_hours as (

    select *
    from {{ ref('int_labor_standard_hours') }}

),

job_header as (

    select company_code, job_num, is_mrp_planning_job
    from {{ ref('stg_ctxepicorkinetic__job_header') }}

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

    standard_hours.production_std_hours_per_unit,
    case
        when labor.labor_type_code = 'S' and not labor.is_rework
            then standard_hours.setup_earned_hours_credit
        else null
    end as setup_earned_hours_credit,                                                  -- SD-26: only exposed on Setup rows, so fct_labor's MAX() naturally scopes the credit to operations with a real Setup transaction -- not every operation that happens to have a populated est_setup_hours

    case
        when labor.labor_type_code = 'P' and not labor.is_rework
            then labor.quantity_produced * standard_hours.production_std_hours_per_unit
        else 0
    end as earned_hours,                                                             -- SD-26

    (labor.labor_type_code = 'P' and not labor.is_rework
        and standard_hours.production_std_hours_per_unit is null) as has_unresolved_standard,

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
