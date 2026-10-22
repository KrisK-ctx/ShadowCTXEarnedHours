select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      -- Singular test: fct_labor's grain (company+job+assembly+operation) must be unique.
-- No dbt_utils available in this build (SD-17) for unique_combination_of_columns,
-- so this is hand-written.

select company_code, job_num, assembly_seqnum, operation_seqnum, count(*) as n
from SANDBOX_EARNEDHOURS_SHADOW.GOLD.fct_labor
group by company_code, job_num, assembly_seqnum, operation_seqnum
having count(*) > 1
      
    ) dbt_internal_test