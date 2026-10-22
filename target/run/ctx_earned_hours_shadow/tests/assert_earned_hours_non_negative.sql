select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      -- Monitoring test: flags rows where earned_hours is negative.
-- Confirmed against live data: every negative case traces to a negative
-- quantity_produced (reversal/correction labor transactions) with a POSITIVE standard
-- rate -- never a negative rate. This is legitimate Epicor behavior (the native EARNEDHRS
-- formula would go negative in the same cases), so this is a warn-severity monitor,
-- not a hard failure.



select *
from SANDBOX_EARNEDHOURS_SHADOW.SILVER.int_labor_detail
where earned_hours < 0
      
    ) dbt_internal_test