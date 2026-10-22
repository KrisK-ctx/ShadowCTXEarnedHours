
  
    

        create or replace transient table SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__job_operation
         as
        (

-- Bronze: Kinetic job operations -- the only place Kinetic standard hours live.
-- Thin rename only. Gated by the enrollment view (SD-10). Carries BOTH candidate
-- standards (est_production_hours = budget, NOT earned hours; production_standard_raw +
-- standard_format = the per-unit rate Silver must convert and multiply by quantity
-- produced -- SD-11). No conversion happens here; that is Silver's job.

with source as (

    select
        company                 as company_code,
        trim(jobnum)            as job_num,
        assemblyseq             as assembly_seqnum,
        oprseq                  as operation_seqnum,
        opcode                  as operation_code,
        subcontract             as is_subcontract,
        runqty                  as run_quantity,
        estsethours             as est_setup_hours,
        estprodhours            as est_production_hours,
        prodstandard            as production_standard_raw,
        stdformat               as standard_format,
        stdbasis                as standard_basis,
        opsperpart              as ops_per_part,
        qtyper                  as quantity_per,
        actprodhours            as act_production_hours,
        actsetuphours           as act_setup_hours,
        qtycompleted            as quantity_completed,
        jobengineered           as is_job_engineered,
        opcomplete              as is_operation_complete,
        jobcomplete             as is_job_complete,
        sysrevid                as _sysrevid
    from MATILLION_RAW.CRETEX_EPICOR_KINETIC.ERP_JOBOPER

)

select source.*, current_timestamp() as _loaded_at
from source
inner join SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__company_enrollment as gate
    on source.company_code = gate.company_code
where source.company_code <> '000000'  -- junk placeholder company, not a real enrolled company
        );
      
  