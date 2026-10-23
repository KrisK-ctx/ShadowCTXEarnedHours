
        

    
        create or replace dynamic table SANDBOX_EARNEDHOURS_SHADOW.GOLD.fct_labor
        target_lag = '1 hour'
        warehouse = COMPUTE_WH_CTX_SCIMDEFAULT
        refresh_mode = INCREMENTAL

        initialize = ON_CREATE

        as (
            

-- Gold: the central fact, aggregated to company + job + assembly_seqnum + operation_seqnum
-- -- the SAME grain as the reconciliation target (CTX_EARNED_HOURS_PRD.GOLD.
-- EARNED_HOURS_JOB_OPERATION), confirmed via its own column list, so the next
-- (reconciliation) step can compare row-for-row without a re-aggregation first.
--
-- department is deliberately NOT joined here -- production's own target grain doesn't
-- carry it either (dim_department exists for future grains, not this one).
--
-- earned_hours is sourced from int_labor_standard_hours.operation_earned_hours (SD-19,
-- revised) -- QUANTITY_COMPLETED-driven -- NOT summed from labor transactions. See that
-- model's header for the corrected root-cause history (SD-20 retracted, SD-22 case fix,
-- SD-24 implemented: zero-standard setup-only operations now credit est_setup_hours
-- only when actual setup labor was posted, validated cross-company (SD-22 case fix,
-- SD-24 conditional rule).

with labor as (

    select *
    from SANDBOX_EARNEDHOURS_SHADOW.SILVER.int_labor_detail

),

standard_hours as (

    select company_code, job_num, assembly_seqnum, operation_seqnum,
           operation_earned_hours, quantity_completed
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
        sum(earned_hours)                                               as txn_summed_earned_hours_crosscheck,
        sum(case when has_unresolved_standard then 1 else 0 end)        as txns_no_computable_standard,

        min(try_cast(clock_in_date_text as date))                       as first_labor_date,
        max(try_cast(clock_in_date_text as date))                       as last_labor_date,

        sum(native_earned_hours_crosscheck)                             as native_earned_hours_crosscheck

    from labor_with_part
    group by company_code, job_num, assembly_seqnum, operation_seqnum

)

select
    aggregated.*,
    standard_hours.operation_earned_hours                               as earned_hours,
    standard_hours.quantity_completed                                   as quantity_produced
from aggregated
left join standard_hours
    on  aggregated.company_code     = standard_hours.company_code
    and aggregated.job_num          = standard_hours.job_num
    and aggregated.assembly_seqnum  = standard_hours.assembly_seqnum
    and aggregated.operation_seqnum = standard_hours.operation_seqnum
        )

    


    