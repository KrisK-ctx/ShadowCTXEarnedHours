-- Reconciliation (diagnostic, point-in-time -- NOT a permanent pipeline layer). Compares
-- this build's fct_labor against the production reconciliation target at the SAME grain:
-- company+job+operation_seqnum (LOT is always NULL for Kinetic -- confirmed against live
-- data, so it is dropped; assembly_seqnum is summed away here too -- checked that every
-- job+operation combo with >1 assembly is an MRP-D% placeholder planning job with zero
-- real labor, so this causes no practical divergence for real production jobs).
--
-- This view's purpose is transitional: once a decision is made on this build vs.
-- production, it has done its job and can be retired -- unlike Bronze/Silver/Gold, which
-- are meant to persist regardless of outcome.

with shadow as (

    select
        company_code,
        job_num,
        operation_seqnum,
        sum(earned_hours)                     as earned_hours,
        sum(actual_hours)                     as actual_hours,
        sum(quantity_produced)                as quantity_produced,
        sum(labor_txns)                        as labor_txns,
        max(employees_involved)                as employees_involved,
        sum(txns_no_computable_standard)       as txns_no_computable_standard,
        max(is_mrp_planning_job)               as is_mrp_planning_job,
        max(case when part_dim_key is null then 1 else 0 end) as part_unmatched
    from SANDBOX_EARNEDHOURS_SHADOW.GOLD.fct_labor
    group by company_code, job_num, operation_seqnum

),

production as (

    select
        company_code,
        job                                    as job_num,
        operation_seqnum,
        earned_hours                           as prod_earned_hours,
        actual_hours                           as prod_actual_hours,
        quantity_produced                      as prod_quantity_produced,
        labor_txns                             as prod_labor_txns,
        employees_involved                     as prod_employees_involved
    from CTX_EARNED_HOURS_PRD.GOLD.EARNED_HOURS_JOB_OPERATION
    where company_code in ('CTX11002', 'CTX11003', 'CTX11101')

)

select
    coalesce(shadow.company_code, production.company_code)      as company_code,
    coalesce(shadow.job_num, production.job_num)                as job_num,
    coalesce(shadow.operation_seqnum, production.operation_seqnum) as operation_seqnum,

    shadow.earned_hours                        as shadow_earned_hours,
    production.prod_earned_hours,
    shadow.earned_hours - production.prod_earned_hours            as delta,
    case
        when production.prod_earned_hours = 0 or production.prod_earned_hours is null then null
        else (shadow.earned_hours - production.prod_earned_hours) / abs(production.prod_earned_hours)
    end                                         as pct_diff,

    case
        when shadow.company_code is null then 'ONLY_IN_PROD'
        when production.company_code is null then 'ONLY_IN_SHADOW'
        when abs(coalesce(shadow.earned_hours, 0) - coalesce(production.prod_earned_hours, 0)) <= 0.01 then 'MATCH'
        else 'MISMATCH'
    end                                         as match_category,

    shadow.actual_hours                        as shadow_actual_hours,
    production.prod_actual_hours,
    shadow.quantity_produced                   as shadow_quantity_produced,
    production.prod_quantity_produced,
    shadow.labor_txns                          as shadow_labor_txns,
    production.prod_labor_txns,

    shadow.txns_no_computable_standard,
    shadow.part_unmatched,
    shadow.is_mrp_planning_job

from shadow
full outer join production
    on  shadow.company_code     = production.company_code
    and shadow.job_num          = production.job_num
    and shadow.operation_seqnum = production.operation_seqnum