# Solution Architecture Document (SAD) — ShadowCTXEarnedHours

**Status:** Bronze/Silver/Gold live and reconciled. Semantic layer not yet built.
**Audience:** Architects reviewing this as a comparative demonstration against production `CTXEarnedHours`.
**See also:** `docs/PROJECT_LOG.md` for the full decision log (SD-01…SD-26) and timeline backing every claim in this document.

> **Layer definitions used in this project:** Bronze = filtered, renamed landing layer (not a RAW/audited exact-copy layer with a data-move date). Silver = business-rule computation. Gold = persisted dimensional model (not views). These are this project's working definitions, not a universal medallion standard, and are flagged explicitly because stricter definitions are a live, open discussion with reviewers — see `docs/DATA_ARCHITECTURE.md` Section 3 and `docs/HIGH_LEVEL_DESIGN.md` for the fuller treatment.

---

## 1. Business Context

Cretex's production Earned Hours pipeline (`CTXEarnedHours`) computes manufacturing earned-hours and efficiency metrics across multiple ERPs (Epicor Kinetic, ProfitKey) and feeds Power BI. This project is a **Skunkworks shadow build**: a small, well-documented re-implementation of the same metric, scoped to the three companies currently enrolled in Kinetic (QTS/CTX11003, CDT/CTX11002, CCR/CTX11101), built to demonstrate an AI-first, Snowflake-native architecture framework (the DAMA Operating Model) against the existing production design.

**This is a comparative demonstration, not a migration or cutover.** No production object is touched; the sandbox is isolated, cost-capped, and time-boxed.

### Success criteria
1. **Match** the published numbers in `CTX_EARNED_HOURS_PRD.GOLD.EARNED_HOURS_JOB_OPERATION` at the agreed grain — the acceptance bar.
2. Where it doesn't match, produce a **diagnosis**, not a shrug: classify every delta as a derivation difference, denominator choice, exclusion rule, or genuine data-quality defect.
3. Demonstrate the framework paying off in the build itself: fewer physical objects, one semantic layer instead of per-grain rollup tables, conformed dimensions instead of a wide flat fact, and codified rules instead of embedded tribal knowledge.

### Current result
CDT 96.66% row-match (-0.72% aggregate), QTS 99.80% (-0.0003%), CCR 95.45% (+0.19%) — achieved only after rebuilding the earned-hours formula from production's own documented business rule (SD-26), not from reverse-engineering reconciliation deltas.

---

## 2. Component Inventory

| Component | Purpose |
|---|---|
| Database `SANDBOX_EARNEDHOURS_SHADOW` | Isolated sandbox, schemas `BRONZE`/`SILVER`/`GOLD`/`SEMANTIC`/`PUBLIC` |
| Resource monitor `RM_EARNEDHOURS_SHADOW` | 50 credits/month quota, notify at 80%, suspend at 100% |
| API integration `KRISK_GITHUB_API_INTEGRATION` | OAuth2 GitHub App integration scoped to the personal `KrisK-ctx` namespace (production's integration is scoped to `Cretex-Companies` only and rejects this repo) |
| Git-backed workspace `USER$.PUBLIC."ShadowCTXEarnedHours"` | ↔ `github.com/KrisK-ctx/ShadowCTXEarnedHours`, branch-per-step convention from the Gold layer onward |
| dbt project `ctx_earned_hours_shadow` | `dbt_project.yml`, `profiles.yml`, `macros/`, `models/staging\|intermediate\|marts\|reconciliation/`, `tests/` |
| Warehouse `COMPUTE_WH_CTX_SCIMDEFAULT` | Compute for all dbt runs and dynamic table refresh |

---

## 3. End-to-End Data Flow

```
┌─────────────────────────────┐     ┌──────────────────────────┐
│ MATILLION_RAW                │     │ PRD_DW.DATAMART           │
│ .CRETEX_EPICOR_KINETIC       │     │ (reused read-only, SD-18) │
│ ERP_LABORDTL, ERP_JOBOPER,   │     │ V_CRETEX_CALENDAR_DATE_DIM│
│ ERP_JOBHEAD, ERP_EMPBASIC,   │     │ T_DIMPART_ALLERPS         │
│ ERP_JCDEPT, enrollment view  │     └─────────────┬─────────────┘
└───────────────┬──────────────┘                   │
                │ incremental/merge                 │
                ▼                                    │
┌─────────────────────────────┐                     │
│ BRONZE (SANDBOX...SHADOW)    │                     │
│ stg_ctxepicorkinetic__*      │                     │
│ thin rename + upper(trim())  │                     │
│ key standardization (SD-22)  │                     │
└───────────────┬───────────────┘                    │
                │ dynamic_table                       │
                ▼                                      │
┌─────────────────────────────┐                       │
│ SILVER                       │                       │
│ int_labor_standard_hours     │                       │
│ int_labor_detail             │                       │
│ (SD-26 earned-hours formula) │                       │
└───────────────┬───────────────┘                      │
                │ dynamic_table                         │
                ▼                                        ▼
┌───────────────────────────────────────────────────────────┐
│ GOLD                                                        │
│ dim_date, dim_part (reused), dim_employee, dim_department,  │
│ fct_labor (company+job+assembly+operation grain)            │
└───────────────┬───────────────────────────────────────────┘
                │ view (diagnostic, transitional)
                ▼
┌─────────────────────────────┐     ┌──────────────────────────┐
│ PUBLIC                       │────▶│ CTX_EARNED_HOURS_PRD.GOLD │
│ rec_labor_job_operation      │     │ .EARNED_HOURS_JOB_OPERATION│
│ (row-for-row comparison)     │     │ (read-only, reconciliation│
└───────────────────────────────┘     target, SD-09)            │
                                     └──────────────────────────┘

                [ NOT YET BUILT ]
                ┌─────────────────────────────┐
                │ SEMANTIC                     │
                │ Earned Hours / Efficiency %  │
                │ governed metric API          │
                └─────────────────────────────┘
```

---

## 4. Integrations

| System | Role | Access mode |
|---|---|---|
| `MATILLION_RAW.CRETEX_EPICOR_KINETIC` | Primary Kinetic source (labor, job operation, job header, employee, department, enrollment). Database name reflects the actual upstream source as it exists today — a rename is a Cretex data-platform decision outside this document's scope, not yet scheduled | Read-only `SELECT` |
| `PRD_DW.DATAMART` | Reused conformed dimensions (`dim_date`, `dim_part`) | Read-only `SELECT`, per SD-18 |
| `CTX_EARNED_HOURS_PRD.GOLD` / `.SILVER` | Reconciliation target + source-of-truth business rule documentation (SD-26) | Read-only `SELECT` |
| `github.com/KrisK-ctx/ShadowCTXEarnedHours` | Version control | OAuth2 via `KRISK_GITHUB_API_INTEGRATION`, Contents: Read/write |

No outbound writes to any system outside `SANDBOX_EARNEDHOURS_SHADOW` exist anywhere in this architecture (SD-09).

---

## 5. Security & Governance Posture

- **Guardrail (SD-09):** no write operation (CREATE/ALTER/DROP/MERGE/INSERT/UPDATE/GRANT) ever targets an object outside `SANDBOX_EARNEDHOURS_SHADOW`. All reads from `MATILLION_RAW`, `PRD_DW`, and `CTX_EARNED_HOURS_PRD` are `SELECT`-only.
- **RBAC (SD-08):** SYSADMIN-owned, minimal RBAC — no `AR_`/`FR_` application/functional roles provisioned yet. This is explicitly **not Mode 1** (production-governed) maturity. If this build graduates toward replacing part of production, that is a separate, later Mode-1/Mode-2 promotion step with real role-based access control.
- **AI/human boundary (SD-13 framework rule):** CoCo builds and tests in dev; a human approves any promotion beyond this sandbox.
- **No catalog/certification applied** — appropriate for a Skunkworks demonstration, but a gap before this would be discoverable or trusted by other teams.

---

## 6. Non-Functional Requirements

| NFR | Target / current state |
|---|---|
| Cost | Capped at 50 credits/month via `RM_EARNEDHOURS_SHADOW`; suspends account-level work on this DB at 100% |
| Refresh latency | Silver/Gold dynamic tables at `TARGET_LAG='1 hour'`, incremental refresh mode |
| Data isolation | Zero production writes, enforced structurally (separate sandbox DB) and procedurally (SD-09) |
| Scope elasticity | Company scope resolves through the enrollment-gate view, not a hardcoded list — a new Kinetic company (e.g. post-ProfitKey migration) is picked up with zero code change (SD-10) |
| Reconciliation accuracy | ≥95% row-match against production's published Gold fact, currently met for all 3 companies |
| Auditability | Every architectural/business-rule decision logged with rationale in `PROJECT_LOG.md` (SD-## convention), mirroring production's own `DR-##`/`N##` convention |

---

## 7. Explicitly Out of Scope

ProfitKey ingestion (Anoka/Coon Rapids, deferred to phase 2), the parallel QTS semantic-view build, attendance/utilization metrics, any production cutover, and (currently) a Cortex Agent or data-catalog registration — none of these are built or scheduled in this pass.

---

**See also:** `docs/PROJECT_LOG.md` Sections 1–8 for full rationale; `README.md` for the one-line project framing.
