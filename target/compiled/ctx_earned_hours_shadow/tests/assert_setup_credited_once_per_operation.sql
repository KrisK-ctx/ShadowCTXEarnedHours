-- Singular test (SD-26): Setup's earned-hours credit is a FIXED, OPERATION-level amount
-- that must be attributed exactly once per operation, regardless of how many Setup labor
-- transactions exist on it (the historical defect this corrects for -- see
-- int_labor_standard_hours header, job 200013 op 21: a 5-hour setup estimate was being
-- accumulated across 13 labor entries before this was caught and fixed in the referenced
-- business design process).
--
-- Asserts fct_labor.setup_earned_hours equals int_labor_standard_hours's own
-- setup_earned_hours_credit exactly, for every operation that actually HAS at least one
-- Setup labor transaction (operations with no Setup labor legitimately show NULL/0 in
-- fct_labor regardless of what the raw operation-level credit would have been, which is
-- correct, not a defect -- this test is scoped to only the operations where the credit
-- should actually appear). If fct_labor's aggregation ever regresses from MAX() to SUM()
-- (or an equivalent mistake), this test fails rather than silently re-introducing the
-- double-counting defect.

with ops_with_setup_labor as (
    select distinct company_code, job_num, assembly_seqnum, operation_seqnum
    from SANDBOX_EARNEDHOURS_SHADOW.SILVER.int_labor_detail
    where setup_earned_hours_credit is not null
)
select
    f.company_code, f.job_num, f.assembly_seqnum, f.operation_seqnum,
    f.setup_earned_hours, s.setup_earned_hours_credit
from ops_with_setup_labor o
join SANDBOX_EARNEDHOURS_SHADOW.GOLD.fct_labor as f
    on  o.company_code     = f.company_code
    and o.job_num          = f.job_num
    and o.assembly_seqnum  = f.assembly_seqnum
    and o.operation_seqnum = f.operation_seqnum
join SANDBOX_EARNEDHOURS_SHADOW.SILVER.int_labor_standard_hours as s
    on  f.company_code     = s.company_code
    and f.job_num           = s.job_num
    and f.assembly_seqnum   = s.assembly_seqnum
    and f.operation_seqnum  = s.operation_seqnum
where abs(coalesce(f.setup_earned_hours, 0) - coalesce(s.setup_earned_hours_credit, 0)) > 0.01