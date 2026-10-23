

-- Gold: the central fact, aggregated to company + job + assembly_seqnum + operation_seqnum
-- -- the SAME grain as the reconciliation target (CTX_EARNED_HOURS_PRD.GOLD.
-- EARNED_HOURS_JOB_OPERATION), confirmed via its own column list, so the next
-- (reconciliation) step can compare row-for-row without a re-aggregation first.
--
-- department is deliberately NOT joined here -- production's own target grain doesn't
-- carry it either (dim_department exists for future grains, not this one).
--
-- earned_hours is now the sum of two components (SD-26, replaces SD-19/SD-23/SD-24):
-- (1) Production labor's per-transaction earned_hours, summed normally (transaction grain
--     is correct, confirmed against production's own SILVER.FACT_LABOR); and
-- (2) Setup's operation-level credit, added in ONCE via MAX() -- never SUM() -- since it is
--     a fixed per-operation amount, not a per-transaction one. Summing it would
--     double/multiply-count it across however many Setup labor transactions exist on the
--     operation, which is the exact historical defect this rule corrects for (see
--     int_labor_standard_hours header). See that model's header for the corrected
--     root-cause history and the empirical validation (CDT 95.23%, QTS 100.00%, CCR
--     96.89% match against production, all 3 companies).

with labor as (

    select *
    from SANDBOX_EARNEDHOURS_SHADOW.SILVER.int_labor_detail

),

standard_hours as (

    select company_code, job_num, assembly_seqnum, operation_seqnum, quantity_completed
    from SANDBOX_EARNEDHOURS_SHADOW.SILVER.int_labor_standard_hours

),

job_header as (

    select company_code, job_num, part_num, part_revision, is_mrp_planning_job
    from SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__job_header

),

part as (

    select company_id, part_key, part_revision, part_dim_key
    from SANDBOX_EARNEDHOURS_SHADOW.GOLD.dim_part

),

labor_with_part as (

    select
        labor.*,
        job_header.part_num,
        job_header.part_revision,
        part.part_dim_key
    from labor
    left join job_header
        on  labor.company_code = job_header.company_code
        and labor.job_num      = job_header.job_num
    left join part
        on  job_header.company_code                                     = part.company_id
        and job_header.part_num                                         = upper(trim(part.part_key))
        and coalesce(job_header.part_revision, '')                      = coalesce(upper(trim(part.part_revision)), '')

),

aggregated as (

    select
        company_code,
        job_num,
        assembly_seqnum,
        operation_seqnum,
        max(part_dim_key)                                               as part_dim_key,
        max(is_mrp_planning_job)                                        as is_mrp_planning_job,

        count(*)                                                        as labor_txns,
        count(distinct employee_num)                                    as employees_involved,

        sum(actual_hours)                                               as actual_hours,
        sum(quantity_produced)                                          as txn_summed_quantity_produced,
        sum(earned_hours)                                               as production_earned_hours,        -- SD-26
        max(setup_earned_hours_credit)                                  as setup_earned_hours,              -- SD-26: MAX, not SUM
        sum(case when has_unresolved_standard then 1 else 0 end)        as txns_no_computable_standard,

        min(try_cast(clock_in_date_text as date))                       as first_labor_date,
        max(try_cast(clock_in_date_text as date))                       as last_labor_date,

        sum(native_earned_hours_crosscheck)                             as native_earned_hours_crosscheck

    from labor_with_part
    group by company_code, job_num, assembly_seqnum, operation_seqnum

)

select
    aggregated.*,
    coalesce(aggregated.production_earned_hours, 0) + coalesce(aggregated.setup_earned_hours, 0) as earned_hours,  -- SD-26
    standard_hours.quantity_completed                                   as quantity_produced
from aggregated
left join standard_hours
    on  aggregated.company_code     = standard_hours.company_code
    and aggregated.job_num          = standard_hours.job_num
    and aggregated.assembly_seqnum  = standard_hours.assembly_seqnum
    and aggregated.operation_seqnum = standard_hours.operation_seqnum