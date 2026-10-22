{{
    config(
        materialized='dynamic_table',
        target_lag='1 hour',
        snowflake_warehouse='COMPUTE_WH_CTX_SCIMDEFAULT',
        refresh_mode='AUTO'
    )
}}

-- Gold: fiscal calendar, reused read-only from the DW (SD-18) -- not rebuilt.
-- Matches production's own REF_DATE sourcing decision. Key = date_key itself:
-- a date dimension's natural key is already stable and unique, so no hash surrogate
-- is needed here (a deliberate, documented exception to hashing every key).
-- Target lag matches the pipeline's 1-hour cadence (not daily, despite rarely changing)
-- to stay compatible with downstream Dynamic Tables that join it (a Dynamic Table's lag
-- can't be tighter than its upstream's).

select
    onlydate                as calendar_date,
    dateyyyymmdd             as date_key,

    calendaryear             as calendar_year,
    calendarmonth            as calendar_month,
    calendarmonthname        as calendar_month_name,
    calendardayofweekname    as day_of_week_name,

    fiscalyear               as fiscal_year,
    fiscalmonth              as fiscal_month,
    fiscalperiod             as fiscal_period,
    fiscalmonthdisplay       as fiscal_month_display,
    fiscalmonthdisplaysort   as fiscal_month_display_sort,
    fiscalweek               as fiscal_week,
    fiscalweekdisplay        as fiscal_week_display,
    fiscalquarteryear        as fiscal_quarter_year,
    fiscalquarterdisplay     as fiscal_quarter_display,
    fiscalstartofmonth       as fiscal_start_of_month,
    fiscalendofmonth         as fiscal_end_of_month,
    fiscalstartofyear        as fiscal_start_of_year,
    fiscalendofyear          as fiscal_end_of_year,
    isfiscalmonthend         as is_fiscal_month_end

from {{ source('prd_dw', 'V_CRETEX_CALENDAR_DATE_DIM') }}
