# Low-Level Design (LLD) — ShadowCTXEarnedHours

**Audience:** Engineers needing exact table grains, key mappings, and job logic.
**See also:** `docs/TECHNICAL_DESIGN.md` for materialization/orchestration context; `docs/PROJECT_LOG.md` SD-26 for full formula derivation history.

> **Layer definitions used in this project:** Bronze = filtered, renamed landing layer (not a RAW/audited exact-copy layer). Silver = business-rule computation. Gold = persisted dimensional model. See `docs/HIGH_LEVEL_DESIGN.md` for the full callout on why this differs from stricter medallion conventions.

---

## 1. Bronze — Table Grain, Keys, and Source Mapping

### `stg_ctxepicorkinetic__company_enrollment`
- **Materialization:** view
- **Grain:** one row per enrolled company
- **Source:** `MATILLION_RAW.CRETEX_EPICOR_KINETIC.CTXEPICORKINETIC_V_ANALYTICS_COMPANY_ENROLLMENT`
- **Filter:** `isactive = 'Y'`
- **Key columns:** `company_code` (not_null, unique)

### `stg_ctxepicorkinetic__labor_detail`
- **Materialization:** incremental/merge, `unique_key=['company_code','labor_header_seqnum','labor_detail_seqnum']`
- **Grain:** one row per labor transaction
- **Source:** `ERP_LABORDTL`, gated (inner join) on the enrollment view
- **Column mapping (source → Bronze):**

| Source column | Bronze column | Transform |
|---|---|---|
| `company` | `company_code` | none |
| `laborhedseq` | `labor_header_seqnum` | none |
| `labordtlseq` | `labor_detail_seqnum` | none |
| `employeenum` | `employee_num` | `upper(trim())` — SD-22 |
| `labortype` | `labor_type_code` | none |
| `labortypepseudo` | `labor_type_pseudo` | none |
| `rework` | `is_rework` | none |
| `jobnum` | `job_num` | `upper(trim())` — SD-22 |
| `opcode` | `operation_code` | `upper(trim())` — SD-22 |
| `jcdept` | `jc_dept` | `upper(trim())` — SD-22 |
| `resourcegrpid` | `resource_group_key` | `upper(trim())` — SD-22 |
| `laborqty` | `quantity_produced` | none (can be negative — reversals) |
| `earnedhrs` | `native_earned_hours_crosscheck` | none — cross-check only, never authoritative (SD-11) |

### `stg_ctxepicorkinetic__job_operation`
- **Materialization:** incremental/merge, `unique_key=['company_code','job_num','assembly_seqnum','operation_seqnum']`
- **Grain:** one row per job operation
- **Source:** `ERP_JOBOPER`, gated on enrollment view, excludes junk placeholder company `'000000'`
- **Key mapping:** `jobnum`→`job_num` (`upper(trim())`), `opcode`→`operation_code` (`upper(trim())`)
- **Carries:** `estprodhours`→`est_production_hours` (budget estimate), `runqty`→`run_quantity`, `estsethours`→`est_setup_hours`, `setuppctcomplete`→`setup_pct_complete`, `opcomplete`→`is_operation_complete`, `jobcomplete`→`is_job_complete`
- **No conversion logic lives here** — this is a thin rename only; Silver owns derivation.

### `stg_ctxepicorkinetic__job_header`, `__employee`, `__department`
- Thin rename, same `upper(trim())` key-standardization pattern on natural keys (`job_num`, `emp_id`, `jc_dept`).

---

## 2. Silver — Job Logic

### `int_labor_standard_hours` (dynamic_table, `target_lag='1 hour'`)
**Input:** `stg_ctxepicorkinetic__job_operation`

**Output columns (new/derived):**
```sql
production_std_hours_per_unit = est_production_hours / NULLIF(run_quantity, 0)

setup_earned_hours_credit =
    est_setup_hours * CASE
        WHEN is_operation_complete THEN 1.0   -- OPERATION completion only, NOT job completion
        ELSE COALESCE(setup_pct_complete, 0) / 100.0
    END
```
- **Grain:** one row per job operation (same as source).
- **Critical correctness point:** gating must be `is_operation_complete`, NOT `is_operation_complete OR is_job_complete`. Counter-example that disproved the OR-gated version: job 201143 op 10 has `jobcomplete=TRUE` but `opcomplete=FALSE`, `setuppctcomplete=0`; production credits 0 for that operation, not the full `est_setup_hours`.

### `int_labor_detail` (dynamic_table, `target_lag='1 hour'`)
**Inputs:** `stg_ctxepicorkinetic__labor_detail` LEFT JOIN `int_labor_standard_hours` ON `(company_code, job_num, assembly_seqnum, operation_seqnum)`, LEFT JOIN `stg_ctxepicorkinetic__job_header` ON `(company_code, job_num)`

**Grain:** one row per labor transaction (unchanged from Bronze).

**Job logic:**
```sql
earned_hours = CASE
    WHEN labor_type_code = 'P' AND NOT is_rework
        THEN quantity_produced * production_std_hours_per_unit
    ELSE 0
END

setup_earned_hours_credit = CASE
    WHEN labor_type_code = 'S' AND NOT is_rework
        THEN standard_hours.setup_earned_hours_credit     -- from int_labor_standard_hours
    ELSE NULL                                               -- exposed ONLY on Setup rows
END

has_unresolved_standard =
    (labor_type_code = 'P' AND NOT is_rework AND production_std_hours_per_unit IS NULL)
```
- Filter uses raw `labor_type_code` (`'P'`/`'S'`), **not** `labor_type_pseudo` — `labor_type_pseudo` was found blank on 214 real transactions (202 Production + 12 Setup, 459,660 units) where the raw field was correctly populated.
- `earned_hours` can be legitimately negative (reversal transactions: negative `quantity_produced` × positive rate — never a negative rate) and legitimately null (`has_unresolved_standard=TRUE`: orphan operation reference or zero `run_quantity`). Neither is defaulted to zero.

---

## 3. Gold — `fct_labor` (dynamic_table, `target_lag='1 hour'`)

**Inputs:** `int_labor_detail` LEFT JOIN `int_labor_standard_hours` (for `quantity_completed`) LEFT JOIN `stg_ctxepicorkinetic__job_header` (for `part_num`/`part_revision`) LEFT JOIN `dim_part` (case-normalized join: `upper(trim(part_key))`/`upper(trim(part_revision))`)

**Grain:** `company_code, job_num, assembly_seqnum, operation_seqnum` — matches `CTX_EARNED_HOURS_PRD.GOLD.EARNED_HOURS_JOB_OPERATION`'s own grain exactly (confirmed via its column list), so reconciliation needs no re-aggregation. Department is deliberately **not** joined — production's target grain doesn't carry it either.

**Aggregation logic:**
```sql
-- per labor transaction, grouped to operation grain
production_earned_hours = SUM(earned_hours)              -- transaction-level sum is correct
setup_earned_hours      = MAX(setup_earned_hours_credit)  -- MAX, never SUM — fixed per-operation amount
earned_hours             = COALESCE(production_earned_hours, 0) + COALESCE(setup_earned_hours, 0)
```
- **Why `MAX()` not `SUM()` for Setup:** a fixed per-operation amount summed across N Setup transactions on the same operation would multiply-count it. This is the exact historical defect production's own team had already found and fixed once (job 200013 op 21: a 5-hour setup estimate accumulated across 13 labor entries; variance against native `EARNEDHRS` improved from +223% to +0.6% once corrected). `int_labor_detail` exposes the credit only on Setup-type rows specifically so `MAX()` naturally scopes to operations with a real Setup transaction, not every operation with a populated `est_setup_hours`.

**Other aggregated columns:** `labor_txns = COUNT(*)`, `employees_involved = COUNT(DISTINCT employee_num)`, `actual_hours = SUM(actual_hours)`, `txns_no_computable_standard = SUM(CASE WHEN has_unresolved_standard THEN 1 ELSE 0 END)`, `native_earned_hours_crosscheck = SUM(...)` (comparison only).

---

## 4. Test Assertions (exact guard conditions)

| Test file | Guards against |
|---|---|
| `assert_earned_hours_non_negative.sql` | Flags (warn) any `earned_hours` < 0 that doesn't trace to a legitimate reversal pattern |
| `assert_fct_labor_grain_unique.sql` | One row per `(company_code, job_num, assembly_seqnum, operation_seqnum)` in `fct_labor` — hand-written since `dbt_utils.unique_combination_of_columns` is unavailable (SD-17) |
| `assert_setup_credited_once_per_operation.sql` | That `setup_earned_hours` in `fct_labor` equals the Setup credit from exactly one operation-level source, not an accumulation across multiple Setup transactions — the direct regression guard for the job 200013 op 21 defect class |

---

## 5. Reconciliation — `rec_labor_job_operation` (view, `PUBLIC` schema)

Full outer join of `fct_labor` against `CTX_EARNED_HOURS_PRD.GOLD.EARNED_HOURS_JOB_OPERATION` at matching grain (`company+job+operation_seqnum` — `LOT` confirmed always NULL for all 108,966 Kinetic rows in the target, so `assembly_seqnum` divergence across 54 `MRP-D%` placeholder jobs with zero real labor was confirmed immaterial).

**Classification logic:** each row classified `MATCH` / `MISMATCH` / `ONLY_IN_SHADOW` / `ONLY_IN_PROD` by comparing `earned_hours` (and presence) on both sides.

**Current result:** CDT 96.66% row-match (-0.72% aggregate), QTS 99.80% (-0.0003%), CCR 95.45% (+0.19%).

---

**See also:** `docs/PROJECT_LOG.md` SD-15/20/22/26 for the empirical investigation history behind each guard above.
