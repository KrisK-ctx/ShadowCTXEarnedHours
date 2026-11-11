-- back compat for old kwarg name
  
  begin;
    
        
            
                
                
            
                
                
            
        
    

    

    merge into SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__department as DBT_INTERNAL_DEST
        using SANDBOX_EARNEDHOURS_SHADOW.BRONZE.stg_ctxepicorkinetic__department__dbt_tmp as DBT_INTERNAL_SOURCE
        on (
                    DBT_INTERNAL_SOURCE.company_code = DBT_INTERNAL_DEST.company_code
                ) and (
                    DBT_INTERNAL_SOURCE.jc_dept = DBT_INTERNAL_DEST.jc_dept
                )

    
    when matched then update set
        "COMPANY_CODE" = DBT_INTERNAL_SOURCE."COMPANY_CODE","JC_DEPT" = DBT_INTERNAL_SOURCE."JC_DEPT","DEPARTMENT_DESCRIPTION" = DBT_INTERNAL_SOURCE."DEPARTMENT_DESCRIPTION","IS_GLOBAL_JC_DEPT" = DBT_INTERNAL_SOURCE."IS_GLOBAL_JC_DEPT","_SYSREVID" = DBT_INTERNAL_SOURCE."_SYSREVID","_LOADED_AT" = DBT_INTERNAL_SOURCE."_LOADED_AT"
    

    when not matched then insert
        ("COMPANY_CODE", "JC_DEPT", "DEPARTMENT_DESCRIPTION", "IS_GLOBAL_JC_DEPT", "_SYSREVID", "_LOADED_AT")
    values
        ("COMPANY_CODE", "JC_DEPT", "DEPARTMENT_DESCRIPTION", "IS_GLOBAL_JC_DEPT", "_SYSREVID", "_LOADED_AT")

;
    commit;