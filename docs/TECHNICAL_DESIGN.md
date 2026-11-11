# Technical Design Document (TDD/SDD) — ShadowCTXEarnedHours

**Audience:** Engineers implementing, extending, or reviewing the dbt project.
**See also:** `docs/PROJECT_LOG.md` for decision rationale (SD-##); `docs/LOW_LEVEL_DESIGN.md` for table/column-level detail.

> **Layer definitions used in this project:** Bronze = filtered, renamed landing layer (not a RAW/audited exact-copy layer — see `docs/DATA_ARCHITECTURE.md` Section 3). Silver = business-rule computation. Gold = persisted dimensional model (not views). These are this project's working definitions, not a universal medallion standard — flagged explicitly because stricter definitions (e.g. Bronze as an audited RAW copy with a data-move date) are a live, open discussion with reviewers.

---

## 1. Project Structure

```
ctx_earned_hours_shadow/
├── dbt_project.yml
├── profiles.yml
├── macros/
│   ├── generate_schema_name.sql
│   └── generate_surrogate_key.sql
├── models/
│   ├── staging/          (Bronze — SANDBOX_EARNEDHOURS_SHADOW.BRONZE)
│   ├── intermediate/      (Silver — SANDBOX_EARNEDHOURS_SHADOW.SILVER)
│   ├── marts/             (Gold — SANDBOX_EARNEDHOURS_SHADOW.GOLD)
│   └── reconciliation/    (diagnostic — SANDBOX_EARNEDHOURS_SHADOW.PUBLIC)
└── tests/
    ├── assert_earned_hours_non_negative.sql
    ├── assert_fct_labor_grain_unique.sql
    └── assert_setup_credited_once_per_operation.sql
```

Schema routing is config-driven per `dbt_project.yml`, not path-based suffixing — each folder maps to an explicit, fixed schema via the `generate_schema_name` macro override (see Section 3).

---

## 2. Materialization Strategy by Layer

| Layer | `dbt_project.yml` config | Why |
|---|---|---|
| `staging` | `materialized: incremental`, `incremental_strategy: merge` | Source ERPs (Kinetic) have no CDC — a full-extract landing step is unavoidable, but `merge` on a declared `unique_key` turns that into row-level upsert rather than `CREATE OR REPLACE` flush-and-fill, giving Bronze a true row-level history point (SD-03, superseded in mechanism but not intent by SD-12) |
| `intermediate` | `materialized: dynamic_table`, `target_lag='1 hour'`, `refresh_mode='INCREMENTAL'` | Declarative, Snowflake-maintained incremental refresh — the documented preferred pattern for multi-step bronze/silver/gold pipelines (SD-04) |
| `marts` | `materialized: dynamic_table`, `target_lag='1 hour'` | Same rationale; also must stay at the same target-lag cadence as its reference dimensions to avoid a lag-chain violation (see Section 6, incident log) |
| `reconciliation` | `materialized: view` | Explicitly diagnostic/transitional — not a permanent medallion object, so it is cheap and always live, not persisted |

All three dynamic-table models (`int_labor_standard_hours`, `int_labor_detail`, `fct_labor`) run on `snowflake_warehouse='COMPUTE_WH_CTX_SCIMDEFAULT'`.

### Why dbt `materialized='dynamic_table'`, not hand-rolled DDL (SD-12)
dbt-snowflake supports `materialized='dynamic_table'` (v1.11.5+), and Snowflake's own MERGE/upsert guidance recommends dbt's incremental `merge` strategy over hand-rolled SQL. Building this as a real dbt project (vs. ad hoc `sql/bronze/*.sql` scripts run via bash) reconciles two requirements that initially looked like competing directions: the DAMA framework's "single dbt monorepo" rule and Snowflake's own Dynamic Table preference. A material deviation from the original plan, caught before any file was written.

A secondary effect: because Silver (a Dynamic Table) detects changes on Bronze directly via Snowflake's own change-tracking, the originally planned manual `CREATE STREAM` on each Bronze table (SD-03) became unnecessary and was dropped — but `CHANGE_TRACKING=TRUE` must still be explicitly enabled on every Bronze incremental table for this to work.

---

## 3. Macros

### `generate_schema_name(custom_schema_name, node)`
Overrides dbt's default behavior (which suffixes a custom schema onto the target schema) to use the custom schema **exactly as specified** per model config. This is what makes `+schema: BRONZE`/`SILVER`/`GOLD` route models to fixed, predictable schemas regardless of the dbt target/profile schema.

### `generate_surrogate_key(column_list)`
Local ~5-line replacement for `dbt_utils.generate_surrogate_key()`. MD5 of the pipe-delimited, null-safe concatenation of the given columns.

**Why not `dbt_utils` (SD-17):** investigated, not assumed unavailable. The account has a governed `DBT_PACKAGES_EXT_ACCESS` external access integration with `USAGE` already granted to `SYSADMIN` — but `EXTERNAL_ACCESS_INTEGRATIONS` only attaches to a formally deployed `DBT PROJECT` object run via SQL `EXECUTE DBT PROJECT`, not the interactive `dbt <cmd> --project-dir` bash execution this build uses (confirmed against Snowflake's SQL reference). Adopting `dbt_utils` would mean switching the entire execution model to reach one hash-wrapper function — not worth the trade. Documented for future review if a real package need arises.

---

## 4. Orchestration

**Current state:** manual, interactive execution — `dbt compile` / `dbt run --select <layer>` / `dbt test --select <layer>` run from bash by the build agent, per layer, with `--full-refresh` required after schema/logic changes to dynamic tables (a recurring quirk of the dynamic-table change-detection mechanism hit multiple times during this build).

**Not yet built:** any scheduled/unattended trigger. Two paths exist if that becomes a requirement:
1. A Snowflake **Task** wrapping `dbt run` on a cadence — straightforward, but still runs the interactive execution path (no `EXECUTE DBT PROJECT`, so `dbt_utils`/external-access integrations remain unreachable, consistent with SD-17).
2. A formally deployed **`DBT PROJECT`** object run via `EXECUTE DBT PROJECT` — unlocks `EXTERNAL_ACCESS_INTEGRATIONS` (and therefore `dbt_utils` if ever needed) but requires switching the whole execution model.

Production's own `CTXEarnedHours` is deployed as DEV/QA/PRD dbt environments; this shadow build has **dev only** — no QA/PRD promotion path exists yet, consistent with its Skunkworks/Mode-0 governance posture (SD-08).

---

## 5. Environments

| Environment | State |
|---|---|
| `dev` (`profiles.yml` target) | Only environment that exists. Role `SYSADMIN`, database `SANDBOX_EARNEDHOURS_SHADOW`, warehouse `COMPUTE_WH_CTX_SCIMDEFAULT`, default schema `BRONZE` |
| `qa` / `prd` | Not provisioned. Would require a Mode-1/Mode-2 promotion decision (SD-08) before being built — not part of this pass |

---

## 6. Incidents Hit and Fixed During Build (engineering record)

| Issue | Fix |
|---|---|
| Used production's *view* column aliases instead of `T_DIMPART_ALLERPS`'s actual raw column names | Caught by compile error; fixed by checking `INFORMATION_SCHEMA.COLUMNS` directly |
| Dynamic Table lag-chain violation: `fct_labor` at 1-hour lag depending on `dim_part` at 1-day lag | Aligned `dim_part`'s target lag to the same 1-hour cadence as the rest of the pipeline |
| Case-sensitive joins on `job_num`/`part_num`/etc. silently dropped matched rows (same business key stored in mixed case across rows) | `upper(trim())` key standardization (case/whitespace) added to every affected Bronze natural-key column (SD-22) |
| Setup earned-hours double/multiply-counted when multiple Setup labor transactions existed on one operation | Fixed by exposing the per-operation credit only on Setup-type rows in `int_labor_detail`, and aggregating with `MAX()` (never `SUM()`) in `fct_labor`; guarded permanently by `assert_setup_credited_once_per_operation` |
| `labor_type_pseudo` blank on 214 real transactions where raw `labor_type_code` was correctly populated | Switched the Production/Setup filter logic to the raw `labor_type_code` field |

---

## 7. Test Suite

| Test | Scope | Severity |
|---|---|---|
| `not_null`/`unique` on business keys (enrollment, `date_key`, `part_dim_key`, `employee_key`, `department_key`) | Bronze/Gold | error |
| `not_null` on `production_standard_raw` where `standard_format != 'HR'` | Bronze (`job_operation`) | warn |
| `not_null` on `int_labor_detail.earned_hours` | Silver | warn — residual unresolved-standard rows are a monitored, confirmed-legitimate category, not a defect |
| `assert_earned_hours_non_negative.sql` | Silver | warn — legitimate reversal/correction transactions are negative by design |
| `assert_fct_labor_grain_unique.sql` | Gold | hand-written, since `dbt_utils.unique_combination_of_columns` is unavailable (SD-17) |
| `assert_setup_credited_once_per_operation.sql` | Gold | guards the exact historical double-counting defect SD-26 corrects for |

Current pass state: 12/12 Bronze, 27/27 hard + 2/2 warn-as-expected Silver, 12/12 Gold.

---

## 8. Transformation Logic Summary (SD-26 formula, implementation level)

- **Production labor** (`labor_type_code='P'`, non-rework), per transaction: `earned_hours = quantity_produced * (est_production_hours / run_quantity)`. Rate is read directly from Epicor's pre-computed `est_production_hours` — not re-derived from `PRODSTANDARD`/`STANDARD_FORMAT` (SD-14's 9-way conversion only agreed with the simple rate 87.67% of the time).
- **Setup labor** (`labor_type_code='S'`, non-rework): a fixed amount credited **exactly once per operation**: `est_setup_hours * (1.0 if is_operation_complete else setup_pct_complete/100.0)`. Exposed only on Setup-type rows in `int_labor_detail`; aggregated with `MAX()`, never `SUM()`, in `fct_labor`.
- **Indirect/Move/Rework labor**: earns 0 — a real zero, not a null, matching production's own `IS_DIRECT_LABOR` definition.

Full implementation appears in `models/intermediate/int_labor_standard_hours.sql` and `models/intermediate/int_labor_detail.sql`; column-level detail is in `docs/LOW_LEVEL_DESIGN.md`.

---

**See also:** `docs/PROJECT_LOG.md` SD-03/04/12/14/17/22/26 for full rationale.
