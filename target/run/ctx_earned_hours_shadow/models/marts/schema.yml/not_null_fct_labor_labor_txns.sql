select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select labor_txns
from SANDBOX_EARNEDHOURS_SHADOW.GOLD.fct_labor
where labor_txns is null



      
    ) dbt_internal_test