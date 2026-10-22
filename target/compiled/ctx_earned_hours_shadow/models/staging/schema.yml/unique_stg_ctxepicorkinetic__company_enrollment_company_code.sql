
    
    

select
    company_code as unique_field,
    count(*) as n_records

from SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__company_enrollment
where company_code is not null
group by company_code
having count(*) > 1


