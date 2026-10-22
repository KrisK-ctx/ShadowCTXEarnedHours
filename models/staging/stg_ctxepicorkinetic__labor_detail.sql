{{
    config(
        unique_key=['company_code', 'labor_header_seqnum', 'labor_detail_seqnum']
    )
}}

-- Bronze: Kinetic labor detail -- the Kinetic fact source.
-- Thin rename only, no business logic. Gated by the enrollment view (SD-10), not a
-- hardcoded company list. Carries Epicor's native EARNEDHRS through as a plain column --
-- NOT treated as authoritative earned hours (SD-11). The real derivation happens in
-- int_labor_standard_hours (Silver), from the operation's per-unit standard x quantity
-- produced. This column exists here only so Silver can cross-check against it later.

with source as (

    select
        company                 as company_code,
        laborhedseq             as labor_header_seqnum,
        labordtlseq             as labor_detail_seqnum,
        employeenum             as employee_num,
        labortype               as labor_type_code,
        labortypepseudo         as labor_type_pseudo,
        rework                  as is_rework,
        trim(jobnum)            as job_num,
        assemblyseq             as assembly_seqnum,
        oprseq                  as operation_seqnum,
        opcode                  as operation_code,
        jcdept                  as jc_dept,
        resourcegrpid           as resource_group_key,
        laborhrs                as actual_hours,
        burdenhrs               as burden_hours,
        laborqty                as quantity_produced,
        scrapqty                as quantity_scrapped,
        earnedhrs               as native_earned_hours_crosscheck,
        complete                as is_complete,
        opcomplete              as is_operation_complete,
        clockindate             as clock_in_date_text,
        payrolldate             as payroll_date_text,
        fiscalyear              as fiscal_year,
        fiscalperiod            as fiscal_period,
        postedtogl              as is_posted_to_gl,
        wipposted               as is_wip_posted,
        laborrate               as labor_rate,
        burdenrate              as burden_rate,
        sysrevid                as _sysrevid
    from {{ source('ctxepicorkinetic', 'ERP_LABORDTL') }}

)

-- No is_incremental() filter: the source is a full flush-and-fill snapshot (SD-03), so
-- every run re-presents the full filtered set and the merge's unique_key does the
-- row-level insert/update. This does not handle source-side deletes -- acceptable for
-- now, revisit if that becomes material.

select source.*, current_timestamp() as _loaded_at
from source
inner join {{ ref('stg_ctxepicorkinetic__company_enrollment') }} as gate
    on source.company_code = gate.company_code
