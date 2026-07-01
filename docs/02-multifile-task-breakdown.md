# 02 — Multi-File + FIM Auto-Testing: Decisions + Task Breakdown

Companion to `docs/01-multifile-task-support.md`. This doc records the **decisions locked in
the design reviews** (grill sessions, 2026-07-01), the **stress-test findings** that corrected the
plan, and the **ordered, sized task backlog** to implement it. All feasibility is prototype-proven
(see `docs/prototypes/` and `docs/01` Appendix A).

**Two task shapes are covered here** (a third — single-file — already works):
- **Multi-file** task responses (controller + schema + migration …) — §A–§E below.
- **Fill-in-the-middle (FIM)** responses — §F below. The 54 existing FIM subtasks (`_02+` dirs)
  are currently **untested** (only manually proven). §F makes them automatically testable, and
  the mechanism was validated on the full corpus (**54/54 reconstruct + pass; 54/54 mutation-
  exercised**). FIM is **independent of the multi-file work and shippable first** (quick, high-value).

---

## A. Decisions locked (design review)

| # | Decision | Choice | Why |
|---|----------|--------|-----|
| D1 | Execution / integration model | **Extend `eval_task.exs` in-process (B1)**; one BEAM per task via `run_all`'s `System.cmd` | Proven on all 3 archetypes; smallest change; preserves the "own BEAM" isolation guarantee; no external services |
| D2 | Per-task configuration | **Inference-first + optional `manifest.exs`** | Archetype + prefix are reliably inferred from the harness (proven); manifest overrides only what can't be inferred (db, migrations) |
| D3 | Database | **SQLite (file + Sandbox) default now; normalize 018; Postgres deferred** | Postgres not installed here; 018 hardcodes it; SQLite is hermetic + zero-service (032 precedent) |
| D4 | Phoenix infra ownership | **Domain-only bundles; host kit always owns Repo/Endpoint/web-entry/ConnCase/config** | One Tier-B code path (the 016 path); no adapter conflicts; normalize 018 down to domain-only |
| D5 | Tier-B module prefix | **Per-task prefix, inferred + substituted (E2)**; recommend a fixed prefix for NEW tasks | Proven (016 green with inferred `PaginatedList`); no rewrite of existing bundles |
| D6 | Harness quality gate | **Build a "reference-solution-green" validator + fix 021** | Compile-only checks miss runtime bugs like 021's; the gate catches exactly that class |
| D7 | This session's deliverable | **Task split only** (this doc) + promote prototypes + update docs | Prototyping already proved feasibility; hand off implementable units |

---

## B. Stress-test findings (what changed vs. the original plan)

Confirmed empirically via an **integrated evaluator prototype** (`docs/prototypes/eval_multifile.exs`)
that infers archetype+prefix from the harness and routes to Tier A/B:

- ✅ `pure_otp` (task 102) → **18/18**; `plug_selfcontained` (task 021, my minimal solution vs a
  bug-fixed harness) → **20/20**; `phoenix_conncase` (task 016, SQLite kit, inferred prefix) → **14/14**.
- ✅ **Archetype + prefix are inferable from the harness** — no manifest strictly required for the
  common case (basis for D2).

Corrections the stress-test forced into the plan:

- ⚠️ **Postgres unavailable** in this environment (no `psql`/server) → Phase 5 unprototypable; SQLite
  must be the built-and-validated default (D3).
- ⚠️ **018 hardcodes `Ecto.Adapters.Postgres`** in its *own* bundled `repo.ex` + `config/test.exs` →
  the "kit provides the Repo" story breaks when the bundle ships its own infra. Resolved by D4
  (domain-only contract) + normalizing 018.
- ⚠️ **Task 021's harness is broken** — a leftover `conn(...) |> Enum.reduce(headers, ...)` line
  raises `Protocol.UndefinedError` on every request, so all 20 tests fail regardless of solution.
  → D6 (fix 021 + reference-green gate).
- ⚠️ **`validate_harnesses.sh` covers only `tasks/*/`** and only checks *compilation* — it would not
  catch 021's runtime bug. → D6 (validator must RUN the reference solution).
- Note: **task 024** harness has a harmless empty throwaway `defmodule :"TestRouter_…" do end`
  (a smell, not a failure). **Task 019** ships no migration though its tests need an `items` table.

---

## C. Task backlog (ordered, with acceptance criteria)

Sizes: S ≈ ½ day, M ≈ 1–2 days, L ≈ 3–5 days. `→` = depends on. MVP milestone marked ★.

### T1 ★ — Bundle format: parser + validator + spec  · S · (no deps)
Add `EvalTask.Bundle`: `parse/1` (regex over `<file path="…">…</file>`), `materialize/2`
(write blocks into a temp tree honoring `lib/`, `priv/repo/migrations/`, `config/`),
`validate/1`. Document the grammar in `docs/01` §5.
- **`validate/1` rejects**: a `.ex` block with no `defmodule` (fragment — the 017 failure mode);
  duplicate paths; paths escaping the temp root; files outside `lib|priv|config|test`.
- **Accept:** unit tests; parsing the 4 solved bundles yields the correct file lists; 017's
  `router.ex` fragment is **rejected** with a clear message; a `../etc` path is rejected.

### T2 ★ — Manifest: schema + inference + loader  · S · (no deps)
`EvalTask.Manifest.resolve(task_dir, harness_src)` → `%{archetype, prefix, web_prefix, otp_app,
db, migrations, async}`. Load `manifest.exs` if present (overrides), else **infer**: archetype
from harness (`use <X>Web.ConnCase` → `:phoenix_conncase`; `use/import Plug.Test` →
`:plug_selfcontained`; else `:pure_otp`); prefix/web_prefix from the ConnCase module; otp_app via
`Macro.underscore`. Default `db`: `:sqlite` for phoenix/ecto, `:none` otherwise.
- **Accept:** inference matches the archetype table in `docs/01` §4.1 for all 11 tasks; an explicit
  `manifest.exs` overrides inference; unknown archetype → clear error.

### T3 ★ — Tier-A runner (pure_otp + plug_selfcontained) into `eval_task.exs`  · M · → T1, T2
Detect multifile (bundle marker or manifest). Tier-A path: `Kernel.ParallelCompiler.compile(
sources, return_diagnostics: true)` → map diagnostics into the existing `compile_result` shape
→ run harness through the current programmatic `ExUnit`/`FailureCollector` path. Bundle
migrations compiled but not counted as solution warnings.
- **Accept:** 102 grades **18/18**; the promoted 021 solution vs a fixed harness grades **20/20**;
  a non-compiling bundle scores compile-fail with diagnostics (score 0); still one BEAM per task.

### T-021-FIX ★ — Fix the 021 harness dead-code bug  · S · → (independent; do with T3)
Delete the leftover `conn = conn(method, path) |> Enum.reduce(headers, …)` block (lines ~11–19)
in `tasks_multifile/021_…/test_harness.exs`, keeping the corrected assignment.
- **Accept:** a correct solution grades 20/20 (verified with the promoted `sol_021`).

### T4 — Solve the 6 self-contained tasks  · L · → T3
Write `<file>`-bundle solutions for the unsolved self-contained tasks: 020, 021, 022, 023, 024,
025 (Plug.Test / pure GenServer — no host kit). Promote `docs/prototypes/sol_021` as the 021
solution.
- **Accept:** each grades green via the Tier-A path in the real evaluator.

### T5 — Tier-B host kit (Phoenix + SQLite), prefix-parameterized  · L · → T3
Templated kit under `test/support/kits/phoenix/` (`{{PREFIX}}`/`{{WEB}}`/`{{OTP_APP}}`):
`Repo` (SQLite adapter), web-entry (`:controller`/`:router`/`:verified_routes` + `__using__`),
`Endpoint` (`server: false`, `render_errors` → kit `ErrorJSON`, `Plug.Parsers`), `ConnCase`
(`Phoenix.ConnTest` + `Sandbox.start_owner!/stop_owner`). Migration runner: **run bundle
migrations in automatic mode, THEN `Sandbox.mode(:manual)`** (ordering is load-bearing — see
`docs/01` §3 gotchas). File-backed SQLite. Rendered per manifest prefix; injected via the
existing `compile_support/1` seam. Reference: `docs/01` Appendix B (the exact kit that passed 016).
- **Accept:** 016 grades **14/14** through the *real* evaluator (not the prototype); `~p`,
  ConnCase, Sandbox all work; kit modules excluded from scoring (see T7).

### T6 — Normalize + enable the Phoenix tasks (017, 018, 019)  · L · → T5, T8
- **017:** rewrite the router *fragment* into a complete `MyAppWeb.Router` module.
- **018:** strip infra files (`mix.exs`, `config/*`, `application.ex`, `repo.ex`, `endpoint.ex`,
  `soft_crud_web.ex`) → domain-only; adapter now comes from the SQLite kit; keep domain (context,
  schema, controllers, router, JSON views, fallback, migration).
- **019:** add the missing `items` migration; write the solution.
- **Accept:** 016/017/018 grade green; 019 solved + green; all under the domain-only contract.

### T7 — Multi-file scoring (`analyze_source` aggregation)  · S · → T3
Feed `analyze_source` the list of solution `lib/**/*.ex` sources and fold metrics (max line
length; moduledoc/spec/doc presence per policy; TODO/SQLi union; fn/pipe sums). **Exclude** kit,
migration, and config files from analysis.
- **Accept:** a multifile score reflects all solution files; a long line or missing moduledoc in
  any `lib/` file is counted; kit/migration files don't move the score.

### T8 — Authoring contract + reference-green validator  · M · → T3, T5
Document the contract (complete modules at canonical paths; domain-only for Phoenix; complete
migration per touched table; harness references only solution public modules + kit support).
Build `scripts/validate_multifile.sh` (or fold into `validate_harnesses.sh`): for **solved** tasks,
run the reference solution through the evaluator and assert all tests pass; for **unsolved**,
compile the harness + lint for dead-code smells (the 021 pattern). Wire into CI.
- **Accept:** the gate is green on all solved+normalized tasks; it catches a re-introduced
  021-style bug; it flags a fragment bundle (via T1 `validate/1`).

### T9 — Discovery + `run_all` + docs  · M · → T3, T5
Teach `run_all.exs` to also glob `tasks_multifile/*/test_harness.exs`, and `eval_task.exs` to
resolve `tasks_multifile/<name>/`. Include multifile tasks in the report/summary. Update
`README.md` with the multifile contribution flow; add `tasks/multifile_single_shot_prompt.md` +
`tasks/multifile_variation_prompt.md` meta-prompts that enforce the contract (emit `<file>`
blocks, domain-only, complete modules, canonical paths).
- **Accept:** `run_all.exs solution.ex` includes multifile tasks; README documents authoring +
  the meta-prompts produce contract-compliant bundles.

### T10 (deferred) — Postgres path  · L · → T5
Manifest `db: :postgres`; kit variant (`storage_up` → migrate in `:auto` → `Sandbox.mode(:manual)`
→ per-test `start_owner!`); **skip/xfail when no PG server is present**. For tasks needing real
Postgres semantics (JSONB, upserts, concurrent-writer async ConnCase) only.
- **Accept:** a `db: :postgres` task grades green where a server exists and is cleanly skipped
  where it doesn't; SQLite tasks unaffected.

---

## D. Dependency graph & milestones

```
T1 ─┐
T2 ─┼─► T3 ─┬─► T4                 (self-contained tasks gradable)
            ├─► T5 ─┬─► T6         (Phoenix tasks gradable)
            │       └─► T8         (validator/contract)
            ├─► T7                 (scoring)
            └─► T9                 (discovery/docs)
T-021-FIX (independent, bundle with T3)
T5 ─► T10 (deferred: Postgres)
```

- **★ MVP (T1 + T2 + T3 + T-021-FIX):** the evaluator ingests `<file>` bundles and grades the
  `pure_otp` + `plug_selfcontained` archetypes end-to-end. Unlocks **6 tasks** (020–025, 102) with
  zero host-kit work. Smallest shippable slice.
- **Milestone 2 (+ T4):** the 6 self-contained tasks solved + green.
- **Milestone 3 (+ T5, T6, T7):** the 4 Phoenix tasks green under SQLite; multi-file scoring live.
- **Milestone 4 (+ T8, T9):** contract + reference-green CI gate; multifile tasks in `run_all` and
  the contribution docs.
- **Deferred (T10):** Postgres, when a task actually needs it.

## E. Open items still to decide (non-blocking)

1. **Moduledoc policy for scoring (T7):** "present in any solution module" vs "required on every
   `lib/` module." (Recommend: any-module for now; tighten later.)
2. **024's empty throwaway `defmodule`** — clean up during T4 (cosmetic).
3. **Fixed prefix for *new* Phoenix tasks (D5 addendum):** adopt `App`/`AppWeb` for new tasks to
   simplify authoring, while keeping E2 substitution for the existing ones? (Recommend: yes.)
4. **Where the kit lives:** `test/support/kits/phoenix/` templates rendered to a temp support dir
   per eval (recommended) vs generated purely in-memory by the evaluator.

---

## F. Fill-in-the-Middle (FIM) auto-testing — decisions + tasks

**Problem:** 54 FIM subtask dirs (`tasks/<a>_<b>_<name>_0N`, N≥2) hold a `prompt.md` (the whole
module with one function replaced by a `# TODO` marker) + a `solution.ex` (just that function),
but **no `test_harness.exs`** — they have never been auto-tested, only manually eyeballed.

**Mechanism (validated, no manifest needed):**
1. Derive the parent from the dir name: `<a>_<b>_<name>_0N` → `<a>_<b>_<name>_01` (which HAS a harness).
2. Extract the `​```elixir` skeleton from the FIM `prompt.md`.
3. Splice the candidate function at the `# TODO` marker (see conventions below) → a full module.
4. Compile it + run the **parent `_01` harness** against it. Score with the FIM rubric (D-F2).

**Validation (this session — see `docs/prototypes/eval_fim.exs`, `mut_fim.exs`):**
- **54/54** FIM reference solutions reconstruct and pass their parent harness (this also
  *machine-verifies* all 54 references, previously only manual).
- **54/54** pass the **mutation check** (`raise`-body mutant fails the parent harness) → every
  FIM target is genuinely exercised; **none is under-tested**.
- **Discriminates:** a behaviorally-wrong body → tests fail (10/10 on the sample); syntactically
  broken → compile-fail.
- Two splice conventions found and both handled: **stub-body** (`def SIG do  # TODO  end`, 53 dirs)
  and **placeholder-line** (`#TODO defp foo` standing for a whole multi-clause function — 1 dir,
  `004_004_calendarscheduler_02`). Marker forms `# TODO` / `#TODO` / `# TODO:` all absorbed by a
  tolerant regex.

### F.1 Decisions locked (design review 2)

| # | Decision | Choice | Why |
|---|----------|--------|-----|
| F-D0 | Reconstruction source | **prompt.md skeleton** (not the `_01` module) | The `_01` modules drifted after FIM extraction (many "fixed" commits) — `solution.ex` is NOT a substring of any current `_01`. The skeleton is the frozen, self-consistent source. Proven 54/54. |
| F-D1 | Test-coverage trust | **Mutation check in the validator** | A `raise`-body mutant must fail the parent harness; if it passes, the FIM is under-tested. Cheap, automated; audited clean on all 54. |
| F-D2 | Scoring | **FIM-adjusted rubric: analysis on the candidate function only** | Keep tests (parent-harness ratio) + compilation; drop moduledoc/@spec/@doc (N/A for a function); keep line-length/no-TODO/no-SQLi; renormalize. |
| F-D3 | Response handling | **Accept function-only AND whole-module responses** | Strip fences; if `defmodule` present → compile/test directly (no splice); else splice the function. Reference stays function-only. |
| F-D4 | Config | **None — fully inferred** | Parent from dir name; marker in prompt.md; harness reused. No manifest. |

### F.2 Task backlog (FIM)

Sizes as in §C. FIM is **orthogonal to T1–T10** and can ship first.

- **FIM-T1 ★ — FIM reconstruction + runner into `eval_task.exs`** · M · (no deps)
  `EvalTask.Fim`: derive parent; extract skeleton; splice candidate (both conventions: stub-body →
  replace the enclosing `def…end`; placeholder-line → replace the marker line); candidate = strip
  fences, use whole module if it contains `defmodule` else splice (F-D3); compile reconstructed +
  run parent harness through the existing programmatic ExUnit path.
  - **Accept:** all 54 reference FIMs grade green; a wrong body → test failures; bad syntax →
    compile-fail (reproduces `docs/prototypes/eval_fim.exs`).
- **FIM-T2 ★ — FIM discovery in `eval_task.exs` + `run_all.exs`** · S · → FIM-T1
  Resolve a FIM dir (no local harness, has a TODO-marked prompt + a parent `_01` with a harness);
  teach `run_all.exs` to **also enumerate FIM dirs** (they're invisible today — it globs
  `*/test_harness.exs`, and FIM dirs have none). Report them in the summary.
  - **Accept:** `run_all.exs` scores the 54 FIM tasks; a lone `eval_task.exs <task> <var> <subtask>`
    resolves a FIM subtask.
- **FIM-T3 — FIM-adjusted scoring** · S · → FIM-T1
  Apply the current `analyze_source` to **the candidate function text only**, skipping
  moduledoc/@spec/@doc; renormalize weights (F-D2). Compilation + tests unchanged.
  - **Accept:** a FIM score reflects the function's line-length/TODO hygiene + parent-harness pass
    ratio; a function is never penalized for lacking a moduledoc.
- **FIM-T4 — FIM validator (reference-green + mutation)** · S · → FIM-T1
  Extend the reference-green gate (T8): for every FIM dir, (a) reference reconstructs + passes;
  (b) a `raise`-body mutant FAILS (reproduces `mut_fim.exs`). Wire into CI. Catches skeleton↔harness
  drift when a parent `_01` is later edited.
  - **Accept:** gate green on all 54; flags a FIM whose parent harness stops exercising the target.
- **FIM-T5 — Marker/skeleton hygiene** · S · → FIM-T1 (optional)
  Document the accepted marker forms + the two splice conventions; add a `validate/1` that asserts
  exactly one marker per FIM prompt and that the reference reconstructs+compiles. Optionally
  normalize `#TODO`→`# TODO`. (No behavior change — the runner is already tolerant.)
  - **Accept:** every FIM prompt has exactly one resolvable marker; anomalies (e.g. the
    `004_004_calendarscheduler_02` no-space marker) are flagged or normalized.

### F.3 "Won't-miss-anything" — integration notes / gaps found

- **Discovery gap (important):** `run_all.exs` globs `tasks/*/test_harness.exs`; **FIM dirs have no
  harness, so they are silently skipped today** and would remain skipped after the multifile work.
  FIM-T2 closes this — without it, the 54 FIM tasks stay invisible to batch scoring.
- **Three task shapes → detection order** in `eval_task.exs`: (1) FIM (no local harness + TODO
  prompt + parent harness), (2) multi-file (`solution.ex` is a `<file>` bundle), (3) single-file
  (today's path). Detect FIM and multi-file before falling through to single-file.
- **Three scoring rubrics:** single-file (full), multi-file (aggregate over `lib/**`, §T7), FIM
  (function-only, F-D2). Keep them as explicit branches off one scorer.
- **Skeleton is a frozen snapshot:** a FIM `prompt.md` duplicates its parent `_01` module at
  extraction time. If `_01` is later edited, skeletons can drift; the FIM-T4 validator (reference-
  green + mutation) is the drift detector. (Optional future: regenerate skeletons from `_01`.)
- **Out of scope now:** FIM *inside* a multi-file bundle (infill one function of a bundled file) —
  no such tasks exist; a future extension would splice into the right bundle file.

### F.4 Sequencing recommendation
Ship **FIM first** (FIM-T1 + FIM-T2, ~1–2 days): it's independent of the multi-file host kit,
turns 54 already-authored tasks into automatically-tested + machine-verified data immediately, and
the runner is a ~40-line proven prototype. Then proceed with the multi-file MVP (T1–T3 + T-021-FIX).

---

## G. Design review 3 — implementation validation (2026-07-01)

The full plan (multi-file + FIM) was implemented as a **unified prototype evaluator**
(`docs/prototypes/eval_task_v2.exs`) and run against the real corpus. Everything is either
proven-green or precisely-diagnosed. The comprehensive implementation reference — architecture,
scoring, kit spec, FIM spec, validator, discovery, **per-task status matrix**, and a
**known-issues log** — is **`docs/03-implementation-spec.md`**. Highlights + new decisions:

### G.1 Decisions locked (design review 3)

| # | Decision | Choice | Why |
|---|----------|--------|-----|
| S4-D1 | Analysis-score bug | **Fix it (award by pass/fail) + recalibrate** | It's dead code — analysis is always 1.0 today (proven). The 20% weight does nothing. |
| S4-D5 | Credo in analysis | **Drop Credo; renormalize to 8 pts** | Credo is a dep but never run (`credo_issues` hardcoded `[]`) — 2 permanently-free points. |
| S4-D2 | Postgres-needing tasks | **Defer: skip-with-reason via `db: :postgres`** | 017 needs `ILIKE` (SQLite rejects). Preserve zero-service default; build PG kit (docker) as fast-follow. |
| S4-D3 | Kit infra ownership | **Kit provides defaults ONLY when the bundle doesn't** | 018 needs a custom ErrorJSON; unconditional kit definition collides. Bundle may override presentation infra. |
| S4-D4 | Latent task/harness bugs | **Adjudicate per prompt; fix the wrong side; log** | Rollout keeps surfacing them (021 harness, 018 201-vs-200); the validator is the discovery mechanism. |

### G.2 What was proven (see docs/03 §1, §8)
- **Unified evaluator** grades all 3 shapes; single-file scoring **byte-identical** to today (backward-compat).
- **All 7 unsolved self-contained tasks are now solved + green** (020:23, 021:20, 022:23, 023:14,
  024:18, 025:11, plus 102:18) — validated solutions in `docs/prototypes/solutions/`.
- **016 green (14/14)**; **018 green (31/31)** after domain-only normalization + kit ErrorJSON-override;
  **017 blocked on Postgres (ILIKE)**; **019 still needs a solution + migration**.
- **FIM: 54/54** reconstruct + pass through the unified evaluator; **54/54 mutation-exercised**.
- **Discovery: 169 gradable tasks** (111 single + 54 FIM + 4 multifile) — FIM + multifile invisible to `run_all` today.

### G.3 Task changes vs §C / §F

- **NEW · T-SCORE-FIX ★ — Fix analysis scoring** · S · (independent) — award analysis points by the
  pass/fail boolean; **drop Credo**; renormalize to 8 pts (docs/03 §3.1). Update multi-file
  (aggregate) + FIM (function-only) analysis accordingly. **One-time scoring-regime shift** (solutions
  missing `@spec`/`@doc` drop below 1.0). Accept: the degraded-solution test now scores < 1.0 on
  analysis; a spec+doc+moduledoc solution scores full.
- **T4 (self-contained solutions)** — DONE in prototype: promote `docs/prototypes/solutions/020,021,
  022,023,024,025` as the task solutions. Still requires **T-021-FIX** (KI-2) for 021's harness.
- **T5 (Tier-B kit)** — add the **ErrorJSON-override rule** (S4-D3): inject kit presentation infra
  only when the bundle doesn't define it. Add **`db: :postgres` skip-with-reason** plumbing (S4-D2).
- **T6 (normalize Phoenix tasks)** — 016 done; **018** normalize = remove 10 infra files, keep 7
  domain, fix its harness 201/200 (KI-3); **017** → mark `db: :postgres` (skip until PG kit);
  **019** → author solution + `items` migration (KI-5).
- **T8/FIM-T4 (validator)** — the reference-green + FIM-mutation gate (both prototyped:
  `eval_task_v2.exs`, `mut_fim.exs`); must RUN references, not just compile (021-class bugs).
- **Known issues** KI-1..KI-5 tracked in docs/03 §9 (analysis bug, 021 harness, 018 201/200,
  calendarscheduler_02 marker, 019 missing solution+migration).

---

## H. IMPLEMENTED (branch `multifile-fim-eval`, 2026-07-01)

The plan was **executed**. The evaluator now lives in compiled, tested modules under
`lib/eval_task/` (`bundle`, `manifest`, `fim`, `phoenix_kit`, `analysis`, `runner`, `discovery`,
`cli`, `failure_collector`); `scripts/eval_task.exs` is a thin entry point; `scripts/run_all.exs`
discovers all 3 shapes; `scripts/validate.exs` is the reference-green + FIM-mutation gate;
`test/eval_task/` holds unit tests. Full as-built details + discoveries + known-issue resolutions
are in **`docs/03` §12**.

| Task | Status |
|------|--------|
| FIM-T1/T2 (reconstruct + discovery) | ✅ 54/54 green through production `eval_task.exs` |
| T1/T2/T3 (bundle, manifest, Tier-A) | ✅ 020–025, 102 green |
| T-021-FIX (KI-2) | ✅ harness dead-code removed |
| T-SCORE-FIX (KI-1) | ✅ analysis awards by pass/fail; Credo dropped; 8-pt renormalized |
| T5 (Tier-B kit + ErrorJSON override + PG skip) | ✅ 016 (14/14), 018 (31/31), 017 skipped |
| T6 (normalize/enable Phoenix tasks) | ✅ 016/018 normalized; 019 solved (20/20); 017 `manifest.exs db: :postgres` |
| T7 (multi-file + FIM analysis) | ✅ aggregate over `lib/**`; FIM function-only (3-pt) |
| T8 / FIM-T4 (validator) | ✅ `scripts/validate.exs` (reference-green + `raise`-mutant) |
| T9 (discovery + run_all) | ✅ 176 tasks discovered (111+11+54); run_all rewritten |
| T10 (Postgres) | ⏸ deferred — 017 skips cleanly via `db: :postgres` |

**Discoveries fixed during execution** (see docs/03 §12): bare-elixir app-starting (Plug/Ecto),
temp-file collision across parallel BEAMs (KI-8), 033_003 fixture/assert mismatch (KI-6, harness
fixed), 097_001 non-ExUnit harness (KI-7, converted). 018 create-status is prompt-ambiguous → not
a bug (KI-3 downgraded).
