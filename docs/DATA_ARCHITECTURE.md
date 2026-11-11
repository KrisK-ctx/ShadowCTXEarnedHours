# Data Architecture Document — ShadowCTXEarnedHours

**Audience:** Data architects/governance reviewers focused on sourcing, storage layering, modeling, and lineage.
**See also:** `docs/HIGH_LEVEL_DESIGN.md` for architectural patterns; `docs/LOW_LEVEL_DESIGN.md` for exact column mappings.

> **Layer definitions used in this project:** Bronze = filtered, renamed landing layer (not a RAW/audited exact-copy layer with a data-move date — see Section 3 below). Silver = business-rule computation. Gold = persisted dimensional model (not views). These are this project's working definitions, not a universal medallion standard, and are flagged explicitly because stricter definitions are a live, open discussion with reviewers.

---

## 1. Sources

| Source | Database.Schema | Role | Access |
|---|---|---|---|
| Kinetic enrollment gate | `MATILLION_RAW.CRETEX_EPICOR_KINETIC.CTXEPICORKINETIC_V_ANALYTICS_COMPANY_ENROLLMENT` | Scope control — which companies are in-pipeline | Read-only |
| Labor detail | `MATILLION_RAW.CRETEX_EPICOR_KINETIC.ERP_LABORDTL` | The fact source — manufacturing labor transactions | Read-only |
| Job operation | `MATILLION_RAW.CRETEX_EPICOR_KINETIC.ERP_JOBOPER` | The only place Kinetic standard hours (rates/estimates) live | Read-only |
| Job header | `MATILLION_RAW.CRETEX_EPICOR_KINETIC.ERP_JOBHEAD` | Job-level attributes (part, revision, MRP flag) | Read-only |
| Employee master | `MATILLION_RAW.CRETEX_EPICOR_KINETIC.ERP_EMPBASIC` | Conformed employee dimension source | Read-only |
| Department master | `MATILLION_RAW.CRETEX_EPICOR_KINETIC.ERP_JCDEPT` | Conformed department dimension source | Read-only |
| Calendar | `PRD_DW.DATAMART.V_CRETEX_CALENDAR_DATE_DIM` | Governed fiscal calendar, reused not rebuilt (SD-18) | Read-only |
| Part dimension | `PRD_DW.DATAMART.T_DIMPART_ALLERPS` | Cross-ERP conformed part dimension, filtered to 3 companies (SD-18) | Read-only |
| Reconciliation target | `CTX_EARNED_HOURS_PRD.GOLD.EARNED_HOURS_JOB_OPERATION` | Production's own published fact — the acceptance bar | Read-only |
| Business-rule reference | `CTX_EARNED_HOURS_PRD.SILVER.FACT_LABOR` (column comments) + Cretex Medallion PoC Earned Hours Business Design Document | The documented formula — used to validate/correct this build's derivation (SD-26) | Read-only / document review |

**Sourcing principle (Category-A reuse-first):** catalog-search before rebuild. `dim_date`/`dim_part` are reused read-only rather than re-platformed, because conformed, governed versions already exist in `PRD_DW`. `MATILLION_RAW` is read directly (not `PRD_DW`'s existing views) because those views structurally exclude QTS and Costa Rica — a confirmed, material gap, not a style preference.

**Note on `MATILLION_RAW` naming:** the database name reflects the actual upstream source as it exists today. Renaming it is a Cretex data-platform decision outside this document's scope — not yet scheduled, and not something this project can decide unilaterally, since production `CTXEarnedHours` and `PRD_DW` also read the same database.

---

## 2. Ingestion Pattern

- **Mechanism:** dbt `incremental` models with `incremental_strategy: merge`, keyed on business keys (e.g. `(company_code, labor_header_seqnum, labor_detail_seqnum)`).
- **Why merge, not pure append or flush-and-fill:** the source ERP has no CDC — every extract is a full snapshot, not a delta. A full `CREATE OR REPLACE` would discard row-level history; `MERGE` on the declared unique key gives true row-level insert/update semantics against the ERP's own primary keys.
- **No `is_incremental()` filtering** in the staging SQL — since the source is itself a full flush-and-fill snapshot, every run re-presents the full filtered set, and the `MERGE`'s unique-key matching (not a timestamp filter) does the incremental work.
- **Known limitation:** this pattern does not handle source-side deletes. Accepted for now; flagged to revisit if it becomes material.
- **Change propagation to Silver:** `CHANGE_TRACKING=TRUE` is enabled on every Bronze incremental table, which is what lets the downstream Dynamic Tables (Silver/Gold) detect and incrementally refresh on Bronze changes without a manually maintained Stream object.

---

## 3. Storage Layer Roles (Bronze / Silver / Gold)

| Layer | Role | What must NOT happen here |
|---|---|---|
| **Bronze** | Landed source data, thin rename, natural-key case/whitespace key standardization (`upper(trim())`) | No business-rule computation, no aggregation, no cross-entity joins beyond the enrollment gate |
| **Silver** | Metric derivation — the earned-hours formula lives here, computed from raw per-unit standards, never from the source's own stored derived value | No multi-entity aggregation to reporting grain — that's Gold's job; this stays at (or near) transaction/operation grain |
| **Gold** | Conformed dimensional model — one fact at the governed comparison grain, dimensions reused or conformed | No per-grain duplication — weekly/monthly/annual rollups are NOT separate Gold tables, they belong in the (future) semantic layer |

This explicit separation of concerns is itself a response to production's identified gap: production's 101-column `SILVER.FACT_LABOR` suggests dimensional attributes were flattened onto the fact instead of conformed out, and production's 7+ duplicate Gold tables suggest grain concerns leaked into physical storage instead of staying a query-time concept.

---

## 4. Dimensional Modeling

**Conformed dimensions (Gold):**
- `dim_date` — reused read-only from `PRD_DW` (key: `date_key`)
- `dim_part` — reused read-only from `PRD_DW`, filtered to the 3 enrolled companies (key: `part_dim_key`)
- `dim_employee` — conformed from Bronze, local surrogate key (key: `employee_key`)
- `dim_department` — conformed from Bronze, local surrogate key (key: `department_key`) — built but **not joined** into `fct_labor`, since production's own target grain doesn't carry department either; retained for future grains

**Fact:** `fct_labor` — grain `company_code, job_num, assembly_seqnum, operation_seqnum`, matching the reconciliation target's own grain exactly so no re-aggregation is needed to compare.

**Surrogate keys:** local `generate_surrogate_key()` macro (MD5 of null-safe pipe-concatenated columns) — no Data Vault, no hash-key framework; this was a frozen framework decision (#16), not reopened for this build.

---

## 5. Lineage (source → consumption)

```
ERP_LABORDTL ──┐
ERP_JOBOPER ───┼──▶ stg_ctxepicorkinetic__* (Bronze)
ERP_JOBHEAD ───┤         │
ERP_EMPBASIC ──┤         │ (merge, keyed, upper(trim) on natural keys)
ERP_JCDEPT ─────┘         ▼
                   int_labor_standard_hours (Silver)
                   int_labor_detail (Silver)
                          │ (dynamic_table, 1-hour target lag)
                          ▼
V_CRETEX_CALENDAR_DATE_DIM ──▶ dim_date  ──┐
T_DIMPART_ALLERPS ───────────▶ dim_part  ──┼──▶ fct_labor (Gold)
stg_ctxepicorkinetic__employee ──▶ dim_employee ──┤
stg_ctxepicorkinetic__department ──▶ dim_department (built, not joined)
                                              │
                                              ▼
                              rec_labor_job_operation (PUBLIC, diagnostic)
                                              │
                        compared against: CTX_EARNED_HOURS_PRD.GOLD.EARNED_HOURS_JOB_OPERATION
                                              │
                                              ▼
                              SEMANTIC (not yet built): Earned Hours, Efficiency %
```

Every column in `fct_labor.earned_hours` traces to exactly two upstream computations — `int_labor_detail.earned_hours` (Production, transaction-grain, `SUM`) and `int_labor_standard_hours.setup_earned_hours_credit` (Setup, operation-grain, `MAX`) — a lineage property directly enforced by the `assert_setup_credited_once_per_operation` test, not left implicit.

---

## 6. Governance Stance

- **Maturity:** Skunkworks / pre-Mode-1. SYSADMIN-owned, minimal RBAC, no `AR_`/`FR_` functional roles yet (SD-08).
- **No catalog registration or certification tag** applied to any object in `SANDBOX_EARNEDHOURS_SHADOW` — intentional for this phase; would be required before this build is discoverable or trusted by other teams, and before any Mode-1/Mode-2 promotion.
- **Data-quality posture:** anomalies are flagged (`has_unresolved_standard`, `warn`-severity tests) rather than silently corrected — a governance principle applied uniformly, not case-by-case.
- **No-write guardrail (SD-09):** structurally enforced by database isolation; procedurally enforced by never issuing a write statement against anything outside `SANDBOX_EARNEDHOURS_SHADOW`. Reconciliation reads `CTX_EARNED_HOURS_PRD` but never writes to it.

---

## 7. Not Yet Built

- **Semantic layer** — the governed metric API (Earned Hours, Efficiency %) that would let reporting grains become queries rather than physical tables. This is the single largest remaining data-architecture gap relative to the stated framework (DAMA Operating Model consumption-contract rule, #14).
- **Lineage registration in a metadata/catalog tool** — lineage above is documented manually; it is not yet visible in a governed lineage graph.
- **Row-level profiling of the residual 3–5% mismatch per company** — the aggregate reconciliation numbers are tight, but the long tail of individual row mismatches hasn't been characterized by root cause.

---

**See also:** `docs/PROJECT_LOG.md` SD-01/02/10/11/17/18/22/26 and Section 6 ("Current state") for the live, verified inventory this document summarizes.
