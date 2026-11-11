# High-Level Design (HLD) — ShadowCTXEarnedHours

**Audience:** Architects evaluating the architectural blueprint and patterns, independent of implementation detail.
**See also:** `docs/SOLUTION_ARCHITECTURE.md` for business context; `docs/TECHNICAL_DESIGN.md` for implementation; `docs/LOW_LEVEL_DESIGN.md` for build-level detail.

> **Layer definitions used in this project:** Bronze = filtered, renamed landing layer (not a RAW/audited exact-copy layer — the source itself is a flush-and-fill snapshot with no retained arrival-date history). Silver = business-rule computation. Gold = persisted dimensional model (not views). These are this project's working definitions, not a universal medallion standard — called out explicitly since stricter definitions are a live, open discussion with reviewers.

---

## 1. Layered Blueprint

```
┌────────────────────────────────────────────────────────────┐
│  SEMANTIC            (not yet built)                        │
│  Governed metric API: Earned Hours, Efficiency %            │
│  Declared grain → weekly/monthly/annual/by-level = queries  │
└───────────────────────▲──────────────────────────────────────┘
                         │
┌────────────────────────────────────────────────────────────┐
│  GOLD                 Dimensional model                     │
│  Conformed dims + one central fact at the comparison grain  │
└───────────────────────▲──────────────────────────────────────┘
                         │
┌────────────────────────────────────────────────────────────┐
│  SILVER                Business-rule computation            │
│  Metric derivation, recomputed from raw fields,              │
│  never trusting the source system's own stored value         │
└───────────────────────▲──────────────────────────────────────┘
                         │
┌────────────────────────────────────────────────────────────┐
│  BRONZE                Landed, filtered, renamed source data │
│  Thin rename + key standardization, no business logic        │
└────────────────────────────────────────────────────────────┘
```

Each layer has exactly one job. Bronze never computes; Silver never aggregates across grain; Gold does not re-derive a *rate* — but it is not business-logic-free either: it performs the final cross-component aggregation (`SUM()` of Production + `MAX()` of Setup, then combined) that produces the reported `earned_hours` figure. That combination is Gold-layer business logic in its own right, distinct from rate derivation, and is called out explicitly here rather than implied away. Semantic never stores a materialized duplicate per reporting grain.

---

## 2. Architectural Patterns Adopted

| Pattern | What it means here |
|---|---|
| **Declarative pipeline, not scheduled ELT** | Silver/Gold are Dynamic Tables with `TARGET_LAG`, Snowflake-maintained — not dbt running on a cron task |
| **Enrollment-gate pattern** | Scope (which companies/business units are in-pipeline) resolves through a single gate view, never a hardcoded list — new entities arrive with zero code change |
| **Recompute, don't trust the source's stored derivation** | The source ERP's own computed value is retained only as a cross-check column; the metric is always rebuilt from raw inputs in Silver |
| **Single fact at a declared grain + governed metric layer**, not grain-proliferation | One Gold fact; multiple reporting grains are a Semantic-layer query concern, not N materialized tables |
| **Conformed dimensions over wide flat facts** | Attributes live on dimensions (reused where already governed, e.g. `dim_date`/`dim_part`), not flattened onto the fact |
| **Codified, testable business rules**, not comments | Rules like "Setup credited once per operation" are enforced by a named dbt test, not a tribal-knowledge comment |
| **Two-layer consumption contract** | Dimensional model answers "what exists / how it joins"; a semantic view (planned) is the separate, governed API defining the metric once |
| **Framework as reference, not scripture** | Every pattern — from DAMA or from production — is independently validated against current platform capability before being adopted; deviations are logged, not silently absorbed |

---

## 3. Platform Choices

| Concern | Choice |
|---|---|
| Transformation framework | dbt (single monorepo layout: `stg_` → `int_` → `dim_`/`fct_`) |
| Refresh mechanism | Snowflake Dynamic Tables (declarative), landing + merge for Bronze (no CDC on source) |
| Surrogate keys | Local macro, MD5-based — no Data Vault, no hash-key framework (frozen decision) |
| Version control | Git-backed Snowsight workspace, branch-per-step from Gold layer onward |
| Isolation boundary | A dedicated sandbox database with its own resource monitor — not a shared or production-adjacent database |

---

## 4. Comparison Against Production's Architecture

| Dimension | Production (`CTXEarnedHours`) | This build |
|---|---|---|
| Consumption layer | None — Power BI reads Gold directly | Dimensional model + planned semantic view |
| Grain handling | 7+ near-duplicate Gold tables per grain (`_WEEKLY`, `_MONTHLY`, `_ANNUAL`, `_BY_LEVEL` via `GROUPING SETS`, plus `RPT_*` variants) | One fact; grain exposed via semantic queries |
| Parallel builds | A second, unreconciled build (`CTX_CORTEX.EARNED_HOURS`) computes the same metric differently for QTS | Single build, single source of truth for this metric |
| Fact width | 101-column `SILVER.FACT_LABOR` — dimensional attributes flattened onto the fact | Conformed dimensions, narrower fact |
| Rule documentation | Tribal-knowledge inline comments (`N31`, `DR-04`, `Q-17`, etc.) | Dedicated dbt tests encode rules as enforced, testable logic |
| Environments | DEV/QA/PRD | dev only (Skunkworks scope) |

This comparison is the explicit point of the exercise (Section 3 of `PROJECT_LOG.md`), not an incidental side effect.

---

## 5. Explicit Non-Goals (This Pass)

- ProfitKey ingestion (Kinetic is the canonical/target shape; ProfitKey conforms to it when built, not the reverse — deferred to phase 2)
- The parallel QTS semantic-view effort
- Attendance/utilization metrics
- Any production cutover or replacement
- A Cortex Agent / Snowflake Intelligence surface (would be new scope, and should wait until the semantic view exists so it doesn't repeat production's "no semantic layer" gap)
- Data catalog registration / certification (appropriate for Skunkworks maturity; a Mode-1/Mode-2 promotion concern, not this pass's)

---

**See also:** `docs/PROJECT_LOG.md` Section 2 (framework rules) and Section 3 (production gap analysis).
