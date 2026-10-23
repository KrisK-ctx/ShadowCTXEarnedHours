
  
    

        create or replace transient table SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__department
         as
        (

-- Bronze: Kinetic job-costing department master. Thin rename only.
-- Gated by the enrollment view (SD-10).
--
-- SD-22: jc_dept is normalized with upper(trim()) defensively, for join consistency
-- with the other models' jc_dept -- confirmed 0 case variance in this table itself.

with source as (

    select
        company                 as company_code,
        upper(trim(jcdept))     as jc_dept,
        description             as department_description,
        globaljcdept            as is_global_jc_dept,
        sysrevid                as _sysrevid
    from MATILLION_RAW.CRETEX_EPICOR_KINETIC.ERP_JCDEPT

)

select source.*, current_timestamp() as _loaded_at
from source
inner join SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__company_enrollment as gate
    on source.company_code = gate.company_code
        );
      
  