{{
    config(
        materialized='dynamic_table',
        target_lag='1 hour',
        snowflake_warehouse='COMPUTE_WH_CTX_SCIMDEFAULT',
        refresh_mode='INCREMENTAL'
    )
}}

-- Silver/intermediate: per-unit Production rate and operation-level Setup credit for every
-- Kinetic job operation.
--
-- SD-26 (REVISED FOUNDATION -- replaces SD-14/SD-19/SD-23/SD-24): the prior several
-- iterations of this model (a 9-way STANDARD_FORMAT conversion from PRODSTANDARD; an
-- operation-level QUANTITY_COMPLETED-driven earned_hours; a conditional zero-standard
-- setup-credit rule) were all built by reverse-engineering empirically from reconciliation
-- data, not from the actual documented business rule. Reading production's own Silver
-- column comments directly (CTX_EARNED_HOURS_PRD.SILVER.FACT_LABOR) plus the Cretex
-- Medallion PoC Earned Hours Business Design Document surfaced the real rule, which is
-- simpler than anything previously built here:
--
--   Production-type labor (labortypepseudo='P', non-rework): earns
--   quantity_produced * (est_production_hours / run_quantity) per transaction.
--   Kinetic's standard rate is read directly from Epicor's own pre-computed
--   est_production_hours, NOT re-derived from PRODSTANDARD/STANDARD_FORMAT -- Epicor
--   already applied whatever internal format math applies when it computed that
--   estimate, so re-deriving it from raw fields was duplicating (and, per the 87.67%
--   agreement rate measured empirically, occasionally disagreeing with) work Epicor had
--   already done correctly.
--
--   Setup-type labor (labortypepseudo='S', non-rework): earns a FIXED amount per
--   OPERATION (never multiplied by quantity -- "Setup is a FIXED amount per operation,
--   so dividing it by pieces is a category error", per production's own column
--   documentation), credited ONCE regardless of how many Setup labor transactions exist
--   on that operation. This mirrors a documented historical defect in the Cretex
--   business-design process itself: multiple Setup time entries against the same
--   operation were once double/multiply-counting the setup budget (job 200013 op 21,
--   a 5-hour setup estimate, was being accumulated across 13 labor entries before this
--   was caught and fixed -- variance against Epicor's native EARNEDHRS improved from
--   +223% to +0.6% for affected operations). The earned amount is
--   est_setup_hours * (1.0 if the operation or job is complete, else
--   setup_pct_complete / 100.0) -- SETUPPCTCOMPLETE is Epicor's own cumulative
--   percent-complete field for the setup function on that operation.
--
--   EARNED_HOURS_RAW_UNPRORATED / PERCENT_ALLOCATED (production's proration columns) are
--   confirmed ProfitKey-specific (NULL on Kinetic, which has no equivalent) -- that
--   mechanism is correctly out of scope here.
--
-- Validated against production's actual EARNED_HOURS_JOB_OPERATION, full 3-company
-- population, before implementing: CDT 95.23% match (+0.20% aggregate), QTS 100.00%
-- match (~0.0% aggregate), CCR 96.89% match (+0.10% aggregate) -- an order of magnitude
-- better than every prior empirically-reverse-engineered iteration (best prior: CDT
-- 78.62%/+2.58%, QTS 99.71%/-0.67%, CCR 71.88%/-1.99%).
--
-- This model now carries the Production RATE (per-unit) and the Setup CREDIT
-- (operation-level, already a final amount, not a rate) side by side -- they combine
-- additively at the fct_labor grain, not here, since Production is transaction-driven
-- and Setup is operation-driven.

with job_operation as (

    select *
    from {{ ref('stg_ctxepicorkinetic__job_operation') }}

)

select
    company_code,
    job_num,
    assembly_seqnum,
    operation_seqnum,
    operation_code,
    run_quantity,
    quantity_completed,
    est_production_hours,
    est_production_hours / nullif(run_quantity, 0) as production_std_hours_per_unit,  -- SD-26

    est_setup_hours,
    setup_pct_complete,
    is_operation_complete,
    is_job_complete,
    est_setup_hours
        * case
            when is_operation_complete then 1.0  -- SD-26: OPERATION completion only, NOT job completion -- confirmed empirically (job 201143 op 10: jobcomplete=TRUE but opcomplete=FALSE, setuppctcomplete=0, and production credits 0, not the full est_setup_hours)
            else coalesce(setup_pct_complete, 0) / 100.0
          end as setup_earned_hours_credit,                                           -- SD-26

    is_subcontract
from job_operation
