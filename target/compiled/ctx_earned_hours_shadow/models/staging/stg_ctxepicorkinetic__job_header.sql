

-- Bronze: Kinetic job header. Thin rename only. Gated by the enrollment view (SD-10).
-- planned_start_quantity_not_produced -- renamed from PRODQTY (production's own trap:
-- this is the PLANNED quantity, not what was actually produced; do not mistake it for
-- quantity_produced on labor_detail/job_operation).
--
-- SD-22: job_num, part_num, part_revision are normalized with upper(trim()) -- see
-- stg_ctxepicorkinetic__labor_detail for the empirical case-variance finding. part_num /
-- part_revision case variance is also a contributing cause of the part-match-rate gap
-- (SD-21).

with source as (

    select
        company                             as company_code,
        upper(trim(jobnum))                 as job_num,
        upper(trim(partnum))                as part_num,
        upper(trim(revisionnum))            as part_revision,
        partdescription                     as part_description,
        prodqty                             as planned_start_quantity_not_produced,
        jobtype                             as job_type,
        jobengineered                       as is_job_engineered,
        jobcomplete                         as is_job_complete,
        jobclosed                           as is_job_closed,
        startdate                           as start_date_text,
        duedate                             as due_date_text,
        plant                               as plant,
        (upper(trim(jobnum)) like 'MRP-%')  as is_mrp_planning_job,
        sysrevid                            as _sysrevid
    from MATILLION_RAW.CRETEX_EPICOR_KINETIC.ERP_JOBHEAD

)

-- is_mrp_planning_job: MRP-suggested planning jobs carry large estimated hours against
-- zero produced quantity. They do not affect earned hours (which is driven by quantity
-- produced), but would badly pollute any budget/estimate-side rollup if not flagged --
-- a real source-data fact, not a stylistic choice (confirmed against the production
-- build's own documented investigation of this pattern).

select source.*, current_timestamp() as _loaded_at
from source
inner join SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__company_enrollment as gate
    on source.company_code = gate.company_code