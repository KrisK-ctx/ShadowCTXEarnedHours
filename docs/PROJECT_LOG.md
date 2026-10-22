# Earned Hours Shadow Build — Project Log

**Status:** Gold layer live (conformed dimensions + fct_labor at reconciliation-target grain); two leads identified for the formal reconciliation step (CDT earned-hours gap, part-dimension match-rate gap)
**Last updated:** 2026-10-22
**Owner:** Kris Krachmer, with CoCo (Cortex Code) as the build agent
**Workspace:** `USER$.PUBLIC."ShadowCTXEarnedHours"` → `github.com/KrisK-ctx/ShadowCTXEarnedHours`

This is a living document, not a one-time report. It gets updated in place after each build step so there is one authoritative trail by the time this goes to dev-team review — not a pile of point-in-time snapshots.

---

## 1. Objective

Build a small, well-documented "shadow" version of Earned Hours that follows Cretex's AI-first, Snowflake-native architecture framework (the DAMA Operating Model) properly, and use it as a comparative demonstration against the production `CTXEarnedHours` dbt project — not a replacement effort.

**Success criteria:**
1. **Match** the published numbers in `CTX_EARNED_HOURS_PRD.GOLD.EARNED_HOURS_JOB_OPERATION` at the agreed grain. This is the acceptance bar, not a nice-to-have.
2. Where it **doesn't** match, produce a diagnosis, not a shrug — classify every delta as a derivation difference, a denominator choice, an exclusion rule, or a genuine data-quality defect, and state which side (this build or the original) should change.
3. Demonstrate the framework paying off in the build itself: fewer physical objects, one semantic layer exposing the metric at any grain instead of per-grain rollup tables, conformed dimensions instead of a wide flat fact, and reusable/codified rules instead of embedded tribal-knowledge comments.

This is governed as a **Skunkworks** effort initially: isolated sandbox database, own resource monitor, time-boxed, not touching any production `CTX_EARNED_HOURS_*` object.

**Standing rule on the DAMA framework itself:** the framework is a reference, not scripture — including for the business owner who helped write it. Every pattern, whether sourced from the DAMA Operating Model or from the production build, is evaluated against current Snowflake-native best practice and only adopted if it independently holds up. Material deviations from either source get surfaced and decided explicitly, not silently absorbed. See SD-04/SD-11/SD-12 for examples where this changed the build.

---

## 2. Framework being followed

Per the `DAMA Operating Model` (Data Architecture — shared workspace), the governing rules for this build:

| Decision | Rule |
|---|---|
| Sourcing (#6) | Read from `MATILLION_RAW`, never `PRD_DW` views — they structurally exclude QTS and Costa Rica |
| Modeling pattern | `stg_{source}__{entity}` → `int_{domain}_{entity}` → `dim_*` / `fct_*`, single dbt-style monorepo layout, surrogate keys via `dbt_utils.generate_surrogate_key()` — no hash keys, no Data Vault (#16, frozen) |
| Consumption contract (#14) | Two layers, not one: the dimensional model answers *what exists and how it joins*; a **semantic view is the governed API on top** that defines metrics once. Gold tables are not the end of the line |
| AI/human boundary (#13) | CoCo builds and tests in dev; a human approves promotion to prod. No shortcuts |
| Sourcing hierarchy | Catalog-search-first, reuse-first (Category A > B > C) — specifically to prevent two unreconciled builds answering the same question |

---

## 3. Where the production build (`CTXEarnedHours`) falls short

This is the specific "manual effort" gap this shadow build is meant to demonstrate fixing:

1. **No semantic layer.** Power BI reads Gold tables/views directly; metrics are frozen into materialized SQL instead of governed centrally.
2. **Metric-grain proliferation.** Seven near-duplicate Gold tables carry the same earned-hours facts at different grains (`EARNED_HOURS_JOB_OPERATION`, `_WEEKLY`, `_MONTHLY`, `_ANNUAL`, `_BY_LEVEL` via `GROUPING SETS`, plus `RPT_*` variants), each with hand-written comments warning not to double-count by combining them.
3. **A second, unreconciled parallel build** (`CTX_CORTEX.EARNED_HOURS`, QTS-specific) computes "earned hours" and "efficiency" differently for the same business unit — the exact duplication the Category-A sourcing rule exists to prevent.
4. **A very wide, denormalized central fact** — 101 columns on `SILVER.FACT_LABOR` — suggests attributes that belong on conformed dimensions got flattened onto the fact instead.
5. **Tribal-knowledge comments** (`N31`, `N38`, `N41`, `N42`, `DR-01`, `DR-04`, `Q-17`, `Q-19` scattered through model docs) instead of codified, reusable rules that a systematic build would externalize into seeds/vars/tests once and reuse.

---

## 4. Decision log

Mirrors the `DR-##` / `N##` convention used in the production repo, so this is a familiar format for the dev team.

| ID | Decision | Rationale |
|---|---|---|
| SD-01 | **(Revised)** Kinetic scope is **QTS (CTX11003) + CCR (CTX11101) + CDT (CTX11002)** — all three companies currently enrolled in production's own Kinetic gate, not a narrower slice | Matches production's full current Kinetic footprint exactly (confirmed live: `CTXEPICORKINETIC_V_ANALYTICS_COMPANY_ENROLLMENT` has exactly 3 enrolled rows today). Originally scoped to QTS+CCR only; CDT was missed in the first pass and added once confirmed enrolled. ProfitKey (Anoka/Coon Rapids, division RMS) remains deferred to phase 2 |
| SD-02 | **(Revised)** Kinetic is the **canonical/target shape**; ProfitKey (and any future E10/IQMS) **conform to it**, not the reverse | Independently validated, not just this project's assumption: production's own bronze-layer model comments record the exact decision, dated 2026-09-09 — *"everything is intended to take the shape and terminology that is for Epicor Kinetic ... you're fitting ProfitKey into Kinetic shape."* Adopted because it already held up in production, confirmed by inspecting the actual bronze view DDL, not copied blind |
| SD-03 | **(Superseded in part by SD-12)** Bronze ingestion uses **landing table → `MERGE` into persisted Bronze (keyed on business key)**, not `CREATE OR REPLACE` flush-and-fill | Source ERPs (ProfitKey/Kinetic) have no CDC, so a full-extract landing step is unavoidable — but turning that into row-level MERGE gives Bronze a true row-level history point instead of full-table noise. The original design also called for a manual `CREATE STREAM` on each Bronze table; that's dropped — see SD-12 |
| SD-04 | Silver/Gold use **Dynamic Tables with `TARGET_LAG`**, not dbt running on a scheduled task | Declarative, incrementally maintained by Snowflake. Independently confirmed as Snowflake's own documented preferred pattern for "multi-step declarative pipeline (bronze/silver/gold)" — not just this project's preference. Implemented via dbt's `materialized='dynamic_table'`, not hand-rolled `CREATE DYNAMIC TABLE` DDL — see SD-12 |
| SD-05 | New workspace is **git-backed** (`github.com/KrisK-ctx/ShadowCTXEarnedHours`), not a plain shared workspace | Production `CTXEarnedHours` is git-backed; matching that is a more faithful comparison if part of the point is demonstrating a properly versioned build, not a one-off |
| SD-06 | New API integration `KRISK_GITHUB_API_INTEGRATION` (OAuth2 via Snowflake GitHub App), scoped to `https://github.com/KrisK-ctx/` | The existing `CTX_GITHUB_API_INTEGRATION` is scoped to `https://github.com/Cretex-Companies/` only and rejects this repo's personal namespace outright. OAuth2 chosen over PAT — no token to generate, rotate, or store |
| SD-07 | Sandbox database `SANDBOX_EARNEDHOURS_SHADOW` with `BRONZE`/`SILVER`/`GOLD`/`SEMANTIC` schemas, intentionally **not** reusing or writing into any `CTX_EARNED_HOURS_*` database | Zero risk of touching the production build; `SANDBOX_` prefix matches the Skunkworks naming convention in the operating model |
| SD-08 | Governance posture: own resource monitor, minimal RBAC (SYSADMIN-owned, no `AR_`/`FR_` roles yet) | Nothing here is Mode 1 yet. If this proves the framework and graduates toward replacing part of `CTXEarnedHours`, that's a separate Mode-1/Mode-2 promotion step with real RBAC |
| SD-09 | **Standing guardrail:** no write (CREATE/ALTER/DROP/MERGE/INSERT/UPDATE/GRANT) ever targets an object outside `SANDBOX_EARNEDHOURS_SHADOW`. Reads from `MATILLION_RAW` and `CTX_EARNED_HOURS_PRD` (reconciliation target) are `SELECT`-only | Confirmed explicitly with the business owner: this effort must not modify any existing production object, view, role, or reference doc at any point. Reconciliation compares against production, it never writes to it |
| SD-10 | Company scope always resolves through the **enrollment gate view** (`stg_ctxepicorkinetic__company_enrollment`), never a hardcoded company list | Independently sound (data-driven scope control beats scattered literals), and it matches production's own explicit rule: *"NEVER hardcode a Kinetic company list anywhere ... that is also how Coon Rapids and Anoka arrive after migrating off ProfitKey: one row is added upstream and this project picks them up with no code change."* Adopted on merit, confirmed against production's own bronze-layer comments, not assumed |
| SD-11 | Earned hours is **recomputed** in the Silver/integration layer from the operation's per-unit standard × quantity produced — **never** taken from Epicor's stored `LaborDtl.EARNEDHRS` | Necessary for reconciliation (production itself does not treat the stored value as authoritative — their own cross-check shows it diverging 17.7% on CDT specifically) and independently defensible as a data-quality practice (a value frozen at clock-out that doesn't get restated after a correction). Epicor's native value is retained in Bronze only as a plain cross-check column (`native_earned_hours_crosscheck`) |
| SD-12 | Build as an **actual dbt project** (`dbt_project.yml`/`profiles.yml`/`models/`) using `incremental`+`merge` for Bronze and `dynamic_table` for Silver/Gold — not hand-written SQL scripts executed ad hoc | A material deviation from the original SD-03/SD-04 plan, caught before any file was written: dbt-snowflake supports `materialized='dynamic_table'` (v1.11.5+), and Snowflake's own decision guide states plainly that MERGE/upsert patterns should use dbt's incremental `merge` strategy, not be hand-rolled. This also means Silver (a Dynamic Table) detects changes on Bronze directly — the manual `CREATE STREAM` in the original SD-03 is unnecessary and dropped. Reconciles the DAMA framework's own "single dbt monorepo" decision with the Snowflake-native Dynamic Table preference, which had looked like two competing directions but weren't |
| SD-13 | Earned hours is computed **only** for direct labor (`labor_type_pseudo='P'`, non-rework). Setup/Indirect/rework get a real `0`, not NULL | The reconciliation target (`EARNED_HOURS_JOB_OPERATION`) is itself documented as "direct labor only." Epicor's native rule treats rework as always-zero. Setup's native formula is a running-total calculation across an operation's setup transactions — not reproduced, because it isn't needed for this target |
| SD-14 | Per-unit standard-hours conversion reproduces Epicor's own `ESTPRODHOURS` formulas (9-way `STANDARD_FORMAT` code: `HR`/`PH`/`PM`/`HP`/`MP`/`OH`/`OM`/`CH`/`CP`), inverted to a per-unit rate and multiplied by **quantity produced**, not planned quantity | Grounded against live data before coding: `STDBASIS` is always `'E'` in this data (no `C`/`M`/`T` in use, though handled); `QTYPERCYCLE` (needed for `CH`/`CP`) is fully populated for all 738 `CH` rows. Unrecognized formats resolve to `NULL`, deliberately visible rather than guessed |
| SD-15 | `earned_hours` can be **legitimately negative** (reversal/correction transactions — confirmed every negative case traces to negative `quantity_produced` with a *positive* standard rate, never a negative rate) and **legitimately NULL** for ~1.2% of Production rows (orphan operation reference, or unresolved `standard_format`/zero denominator) — flagged via `has_unresolved_standard`, not defaulted to zero | Caught by running the data tests, not assumed: an initial `not_null` + non-negative test both failed, investigated against live data before relaxing them to `warn`-severity monitors rather than silently coalescing to zero, per "flag bad data, don't silently fix it" |
| SD-16 | From the Gold step onward, use a **short-lived topic branch per build step** (e.g. `gold-layer`), merged to `main` via PR — not direct-to-`main` commits | Bronze and Silver were committed straight to `main`; left as-is, not rewritten. SD-05 justified a git-backed workspace specifically to mirror production's versioning rigor — direct-to-`main` undercut that. No branch protection or required reviewers, since this is solo work and that would be process theater with no second reviewer. The PR history doubles as a lightweight, reviewable summary per step alongside this log |
| SD-17 | No `dbt_utils` — a local ~5-line `generate_surrogate_key` macro instead | **Investigated, not assumed**, after being challenged on it: the account already has a governed `DBT_PACKAGES_EXT_ACCESS` external access integration (created 2026-05-21) with `USAGE` already granted to `SYSADMIN`, so `dbt_utils` is technically reachable. But `EXTERNAL_ACCESS_INTEGRATIONS` only attaches to a **formally deployed `DBT PROJECT` object** run via SQL `EXECUTE DBT PROJECT` — confirmed against Snowflake's own SQL reference and troubleshooting docs — and has no effect on the interactive `dbt <cmd> --project-dir` bash execution this whole build uses. Adopting it would mean switching the entire build's execution model (deploy + `EXECUTE DBT PROJECT` instead of the fast interactive loop) to reach one hash-wrapper function. Not worth the trade; documented here for future review if a real package need ever justifies the switch |
| SD-18 | Reuse two `PRD_DW.DATAMART` objects, **read-only**, for `dim_date` and `dim_part`: `v_cretex_calendar_date_dim` and `T_DIMPART_ALLERPS` (filtered to our 3 companies) | Matches production's own `REF_DATE`/`REF_PART_DIM` sourcing decision — the Category-A "reuse before rebuild" sourcing principle, confirmed accessible before asking (9,502-row calendar; 75,632/10,432/1,180 part rows for QTS/CDT/CCR respectively) and explicitly confirmed with the business owner, since it expands SD-09's read-source list beyond `MATILLION_RAW`/`CTX_EARNED_HOURS_PRD`. The no-writes-outside-sandbox guardrail itself is unaffected |

---

## 5. Timeline

| When | What happened |
|---|---|
| 2026-10-22, architecture review session | Reviewed the deployed `CTXEarnedHours` dbt project (Bronze→Silver→Gold, both ERPs, `CTX_EARNED_HOURS_DEV/QA/PRD`) and summarized its architecture and design on request |
| 2026-10-22, same day | Assignment framed: build a shadow version demonstrating the AI-first/Snowflake-native framework against that production build. Read the `DAMA Operating Model` reference docs (sourcing hierarchy, RBAC/security framework, operating rhythm, decision log) and produced the gap analysis in **Section 3** above |
| 2026-10-22, same day | Entered Plan Mode; drafted the initial build plan (scope slice, workspace/sandbox layout, 8-step build sequence). User refined it twice in review — multi-ERP-by-design (**SD-02**) and the native MERGE+Stream+Dynamic-Table ingestion pattern (**SD-03/SD-04**) — before the plan was finalized |
| 2026-10-22, same day | Workspace setup: chose git-backed over plain shared workspace (**SD-05**); user created `github.com/KrisK-ctx/ShadowCTXEarnedHours`; discovered the existing GitHub API integration was scoped to the wrong GitHub namespace; created `KRISK_GITHUB_API_INTEGRATION` under `ACCOUNTADMIN` (**SD-06**); user connected the git-backed workspace in Snowsight |
| 2026-10-22, same day | Hit a session-level bug where the sandbox's file mount stayed bound to the previous workspace's stage even after switching — resolved by starting a fresh chat session directly in the `ShadowCTXEarnedHours` workspace tab |
| 2026-10-22, 10:16:48 (CST) | `RM_EARNEDHOURS_SHADOW` resource monitor created — 50 credit/month quota, notify at 80%, suspend at 100% |
| 2026-10-22, 10:18:06–10:18:07 (CST) | `SANDBOX_EARNEDHOURS_SHADOW` database created with `BRONZE`, `SILVER`, `GOLD`, `SEMANTIC` schemas — all four schemas provisioned inside roughly one second of each other, each with a comment describing its role in the native-ingestion pattern (**SD-07/SD-08**) |
| 2026-10-22, current session | Confirmed the fresh session is correctly mounted to `ShadowCTXEarnedHours` (only `README.md` present, no stale files); confirmed access to the prior planning thread; authored this project log |
| 2026-10-22, same session | Inspected the actual production `CTXEarnedHours` dbt project (`CTX_EARNED_HOURS_PRD.DBT.CTXEARNEDHOURS`) and its Bronze-layer view DDL directly, at the business owner's request, specifically to validate (not assume) the cross-ERP integration pattern. Confirmed: Kinetic-as-canonical-shape is production's own documented decision (**SD-02 revised**); the enrollment-gate-not-hardcoded-list rule (**SD-10**); CDT's enrollment status, correcting the scope to all three current Kinetic companies (**SD-01 revised**); and that production recomputes earned hours rather than trusting Epicor's stored value (**SD-11**) |
| 2026-10-22, same session | Caught a material deviation before writing any SQL: the original plan (hand-written `sql/bronze/*.sql` scripts run via bash) was checked against current Snowflake documentation and found to conflict with both Snowflake's own guidance and the DAMA framework's "single dbt monorepo" decision. Revised to build as an actual dbt project (**SD-12**) |
| 2026-10-22, same session | Scaffolded the dbt project (`dbt_project.yml`, `profiles.yml`, `macros/generate_schema_name.sql`, `models/staging/`) and built the Bronze layer: `dbt compile` clean, `dbt run --select staging` → 6/6 models succeeded, `dbt test --select staging` → 12/12 tests passed. Row counts spot-checked live against Snowflake, confirming all three companies present: labor_detail (CTX11003: 195,517 / CTX11002: 23,435 / CTX11101: 2,442 rows), plus job_operation, job_header, employee, department |
| 2026-10-22, same session | First commit pushed to `github.com/KrisK-ctx/ShadowCTXEarnedHours` — dbt project scaffold + Bronze layer + project log, confirmed landed in GitHub. Hit and resolved a real permission gap along the way: `KRISK_GITHUB_API_INTEGRATION`'s OAuth identity was authorized for `KrisK-ctx`, but the underlying Snowflake GitHub App had only ever been *installed* on `Cretex-Companies` (confirmed via GitHub's own app page: "snowflakedb has been installed on 1 account you have access to: Cretex-Companies") — identity authorization without an app installation on the target account is not sufficient for write access. Fixed via Workspace Changes tab → **Edit credentials** → **Configure**, which opened GitHub's install page directly; installed the app on the personal `KrisK-ctx` account with `ShadowCTXEarnedHours` selected and Contents: Read/write. Push succeeded immediately after |
| 2026-10-22, same session | Built Silver/intermediate: amended Bronze (added `quantity_per_cycle` to `job_operation`, full-refreshed; enabled `CHANGE_TRACKING=TRUE` on all 5 Bronze incremental tables for downstream Dynamic Table correctness); grounded the `STANDARD_FORMAT` conversion against live data before coding (confirmed `STDBASIS` is always `'E'`, `QTYPERCYCLE` fully populated for all 738 `CH` rows) (**SD-14**); built `int_labor_standard_hours` and `int_labor_detail` as dbt `dynamic_table` models |
| 2026-10-22, same session | First test run failed two tests (`not_null` on `earned_hours`: 2,527 rows; non-negative: 570 rows). Investigated rather than patched: negative values all trace to legitimate reversal/correction transactions (negative `quantity_produced`, never a negative rate); nulls are ~1.2% of Production rows with an unresolved operation standard. Relaxed both to `warn`-severity monitors, added `has_unresolved_standard` for visibility (**SD-15**) — matches production's own `TXNS_NO_COMPUTABLE_STANDARD` column, confirming this is a recognized category, not a modeling error |
| 2026-10-22, same session | Early top-line sanity check (not the formal reconciliation suite) against `CTX_EARNED_HOURS_PRD.GOLD.EARNED_HOURS_JOB_OPERATION`: QTS (CTX11003) within **-0.69%** (325,025 vs. 327,270 hours) — validates the "cleanest documented logic" scoping call. CCR (CTX11101) **-2.38%**, with a ~17% transaction-count shortfall worth investigating. **CDT (CTX11002) -17.69%** (33,460 vs. 40,649 hours) — strikingly close to production's own previously-flagged 17.7% divergence between their recompute and Epicor's native `EARNEDHRS` on CDT specifically; a strong, specific lead for the formal reconciliation step, not yet root-caused |
| 2026-10-22, same session | User asked explicitly whether `dbt_utils` (needed for `generate_surrogate_key()`) was actually investigated rather than assumed unavailable. Re-checked: found a governed `DBT_PACKAGES_EXT_ACCESS` external access integration already in the account with `USAGE` already granted to `SYSADMIN`. Investigated further and confirmed it only attaches to formally deployed `DBT PROJECT` objects via `EXECUTE DBT PROJECT`, not the interactive bash execution this build uses — adopting it would mean switching execution models for one hash function. Decision confirmed: local macro (**SD-17**) |
| 2026-10-22, same session | Created and pushed a `gold-layer` branch (**SD-16**) — first use of the new branch-per-step convention, confirmed landed in GitHub before building on it |
| 2026-10-22, same session | Confirmed read access to two `PRD_DW.DATAMART` objects before asking, then got explicit confirmation to reuse them read-only (**SD-18**): `v_cretex_calendar_date_dim` (`dim_date`) and `T_DIMPART_ALLERPS` (`dim_part`, filtered to our 3 companies) |
| 2026-10-22, same session | Built Gold: `dim_date`, `dim_part`, `dim_employee`, `dim_department`, `fct_labor` as dbt `dynamic_table` models. Hit two real errors, both fixed, not glossed over: (1) used production's *view* column aliases instead of the raw `T_DIMPART_ALLERPS` table's actual column names — caught by the compile error, fixed by checking `INFORMATION_SCHEMA.COLUMNS` directly; (2) a Dynamic Table lag-chain violation (`fct_labor` at 1-hour lag depending on `dim_part` at 1-day lag) — fixed by aligning the reference dimensions to the same 1-hour cadence as the rest of the pipeline. 5/5 models built, 11/11 tests passed (including a hand-written grain-uniqueness test, since `dbt_utils.unique_combination_of_columns` isn't available per SD-17) |
| 2026-10-22, same session | Spot-checked `fct_labor`: totals match Silver exactly (33,460 / 325,025.2 / 13,085 earned hours for CDT/QTS/CCR — no loss in aggregation). New lead surfaced: **part-dimension match rate** is weaker than expected — CTX11002 27% of operations unmatched to `dim_part`, CTX11003 12.6%, CTX11101 negligible (0.1%). Flagged for the formal reconciliation step, not investigated further yet |

**On elapsed time:** from first reading the production architecture to having a governed, cost-capped, schema-structured sandbox live in Snowflake — including discovering and working around a GitHub-integration scoping issue and a session-mount bug — was same-day, with no infrastructure ticket, no manual DBA provisioning request, and no wait time beyond the two issues above. Bronze, Silver, and Gold — including the material-deviation catch (ad hoc SQL → dbt project), a second investigation challenged by the business owner (dbt_utils availability) that led to a confirmed decision rather than an assumption, three test/compile failures investigated and resolved, and two reconciliation leads surfaced (CDT earned-hours gap, part-match-rate gap) — were scaffolded, built, and verified live in the same working session. Semantic has not started yet; this timeline will be extended as it lands.

---

## 6. Current state (verified live against Snowflake, not assumed)

**Exists:**
- Database `SANDBOX_EARNEDHOURS_SHADOW` — schemas `BRONZE`, `SILVER`, `GOLD`, `SEMANTIC`, `PUBLIC`
- Resource monitor `RM_EARNEDHOURS_SHADOW` (50 credits/month, 0 used)
- API integration `KRISK_GITHUB_API_INTEGRATION`
- Git-backed workspace `USER$.PUBLIC."ShadowCTXEarnedHours"` ↔ `github.com/KrisK-ctx/ShadowCTXEarnedHours`
- dbt project `ctx_earned_hours_shadow` (`dbt_project.yml`, `profiles.yml`, `macros/generate_schema_name.sql`, `models/staging/`)
- **Bronze layer, live and tested, in `SANDBOX_EARNEDHOURS_SHADOW.BRONZE`:**
  - `stg_ctxepicorkinetic__company_enrollment` (view) — 3 rows (QTS/CCR/CDT, all active)
  - `stg_ctxepicorkinetic__labor_detail` (incremental/merge) — 221,394 rows across the 3 companies
  - `stg_ctxepicorkinetic__job_operation` (incremental/merge) — 213,818 rows
  - `stg_ctxepicorkinetic__job_header` (incremental/merge) — 19,094 rows
  - `stg_ctxepicorkinetic__employee` (incremental/merge) — 1,004 rows
  - `stg_ctxepicorkinetic__department` (incremental/merge) — 59 rows
  - 12/12 dbt tests passing (`not_null` on business keys, `unique` on the enrollment gate)
  - `CHANGE_TRACKING=TRUE` enabled on all 5 incremental tables; `quantity_per_cycle` added to `job_operation`
- **Silver/intermediate layer, live and tested, in `SANDBOX_EARNEDHOURS_SHADOW.SILVER`:**
  - `int_labor_standard_hours` (dynamic_table) — per-unit standard hours for every job operation, full 9-way `STANDARD_FORMAT` conversion (SD-14)
  - `int_labor_detail` (dynamic_table) — recomputed labor fact, direct-labor-scoped `earned_hours` (SD-13), `has_unresolved_standard` flag (SD-15), native `EARNEDHRS` cross-check carried through
  - 3/3 hard tests passing, 2/2 `warn`-severity monitors firing as expected (2,527 unresolved-standard rows, 570 reversal rows) — both investigated and confirmed legitimate, not defects
  - **Early sanity check vs. production (Section 5):** QTS -0.69%, CCR -2.38%, CDT -17.69% (matches production's own previously-flagged CDT divergence — a named lead for reconciliation)

**Does not exist yet:**
- Any Gold (marts) model — conformed dimensions (`dim_date`, `dim_employee`, `dim_department`, `dim_part`) and `fct_labor` have not been built
- The semantic view
- The formal reconciliation test suite (the Section 5 sanity check is directional only, not row-for-row)
- ProfitKey ingestion (deferred, SD-01)

Anyone reading this log mid-project should take Section 6, not Section 5's narrative tone, as the source of truth for "how far along is this."

---

## 7. Forward plan

- [x] Provision workspace + sandbox DB/schemas/resource monitor
- [x] Bronze layer — dbt incremental/merge models over `MATILLION_RAW.CRETEX_EPICOR_KINETIC` (`ERP_LABORDTL`, `ERP_JOBOPER`, `ERP_JOBHEAD`, `ERP_EMPBASIC`, `ERP_JCDEPT`), gated via the enrollment view, QTS+CCR+CDT, 12/12 tests passing
- [x] Silver/intermediate layer — standard-hours recompute (SD-11/SD-13/SD-14), recomputed `int_labor_detail`, built as dbt `dynamic_table` models (SD-04/SD-12); early sanity check complete with a named lead on CDT
- [ ] Gold/marts — conformed `dim_date` (fiscal), `dim_department`, `dim_part`, `dim_employee` (surrogate keys via `generate_surrogate_key()` — requires adding `dbt_utils`, not yet done), and a single `fct_labor` at job/operation grain, properly dimensionalized, not a wide flat fact
- [ ] Semantic view — Earned Hours, Efficiency %, with declared grain dimensions so weekly/monthly/annual/by-level views are queries, not materialized duplicate tables
- [ ] Formal reconciliation suite — tests tying this build's output back to `CTX_EARNED_HOURS_PRD.GOLD.EARNED_HOURS_JOB_OPERATION` row-for-row at matching grain; classify every delta, starting from the CDT -17.69% lead already identified
- [ ] Diagnose and document every reconciliation delta
- [ ] Final before/after comparison report (object count, manual-effort markers, semantic-layer presence) for dev-team review

## 8. Explicitly out of scope for this pass

ProfitKey (Anoka/Coon Rapids), the parallel QTS semantic-view build, attendance/utilization metrics, and any production cutover. This is a demonstration, reconciled and documented — not a migration.
