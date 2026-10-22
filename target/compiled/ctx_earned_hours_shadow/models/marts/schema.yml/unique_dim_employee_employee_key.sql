
    
    

select
    employee_key as unique_field,
    count(*) as n_records

from SANDBOX_EARNEDHOURS_SHADOW.GOLD.dim_employee
where employee_key is not null
group by employee_key
having count(*) > 1


