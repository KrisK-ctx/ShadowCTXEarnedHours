{{
    config(
        materialized='dynamic_table',
        target_lag='1 hour',
        snowflake_warehouse='COMPUTE_WH_CTX_SCIMDEFAULT',
        refresh_mode='AUTO'
    )
}}

-- Gold: conformed part dimension, reused read-only from the DW (SD-18) -- not rebuilt.
-- Matches production's own REF_PART_DIM sourcing decision. Filtered to our 3 Kinetic
-- companies only (ProfitKey's '14'/'32' excluded -- out of scope per SD-01).
-- Key = part_dim_key, already provided by the DW (company + part + revision, resolved).

select
    companyid_part_rev_source_parthk_key   as part_dim_key,
    company_id,
    part_number                            as part_key,
    revision_number                        as part_revision,
    part_source,
    internal_part_number,
    external_part_number,
    part_desc,
    part_desc_2,
    revshortdesc                           as rev_short_desc,
    revdescription                         as rev_description,
    prod_code                              as product_code,
    type_code,
    part_class_desc,
    commercial_category,
    commercial_sub_category,
    approved,
    approved_date,
    effective_date,
    part_uses_inventory,
    part_deleted_date,
    part_deleted_flag,
    part_rev_deleted_date,
    part_rev_deleted_flag,
    part_intro_date,
    part_age_years,
    part_age_months
from {{ source('prd_dw', 'T_DIMPART_ALLERPS') }}
where company_id in ('CTX11002', 'CTX11003', 'CTX11101')
