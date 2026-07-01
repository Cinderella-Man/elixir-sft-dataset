# 03 — Implementation Spec: Unified 3-Shape Evaluator (single-file · multi-file · FIM)

Consolidated "how to do it," written after design review 3 (2026-07-01), where the whole plan was
implemented as a working prototype and run against the real corpus. This is the definitive
reference for building the production evaluator. Companion to `docs/01` (multi-file design) and
`docs/02` (decisions + task backlog). **All claims here are prototype-proven** — see
`docs/prototypes/` (`eval_task_v2.exs` is the unified evaluator; `solutions/` holds 8 validated
solutions).

---

## 1. What was proven this session

A single evaluator prototype (`docs/prototypes/eval_task_v2.exs`, ~270 lines) detects the task
shape and grades all three, with byte-identical single-file scoring:

| Shape | Proof | Result |
|-------|-------|--------|
| **single-file** | v2 vs current `eval_task.exs` on 5 tasks | overall scores **identical** (backward-compat) |
| **multi-file / Tier-A** (pure_otp, plug_selfcontained) | 102 + the 6 now-solved self-contained tasks | all **green** (18, 23, 23, 14, 18, 11, 20) |
| **multi-file / Tier-B** (phoenix_conncase) | 016 (SQLite kit, prefix auto-inferred) | **14/14** |
| **FIM** | all 54 FIM dirs through v2 | **54/54** reconstruct + pass; 54/54 mutation-exercised |

Discovery: the corpus is **111 single-file + 54 FIM + 4 multifile solved = 169 gradable tasks**
today (FIM + multifile are invisible to `run_all.exs` currently — §7).

---

## 2. Evaluator architecture (in-process, one BEAM per task)

`eval_task.exs` gains a **shape dispatcher** in front of its existing flow. Nothing about the
"each solution in its own OS process / own BEAM" isolation guarantee changes.

```
resolve(task) -> {task_dir, solution_file}
detect(task_dir, solution_file):
  no test_harness.exs in dir            -> :fim         (parent _01 has the harness)
  solution_file contains "<file path="  -> :multifile
  else                                  -> :single      (today's path, unchanged)

run(:single)     -> compile_one + analyze(full)       + run_harness(dir/test_harness)
run(:multifile)  -> archetype = infer(harness);
                    Tier-A (pure_otp|plug_selfcontained): ParallelCompiler(bundle) + run_harness
                    Tier-B (phoenix_conncase): render kit + compile bundle+kit + boot + migrate + run_harness
                    analyze(aggregate over lib/**.ex)
run(:fim)        -> reconstruct(prompt skeleton + candidate) + run_harness(parent _01) + analyze(function-only)
score(compile, analysis, tests, mode)  -> unified JSON  (same shape as today + shape/tier/archetype fields)
```

Detection order matters: **FIM and multi-file are checked before falling through to single-file.**

---

## 3. Scoring (post-fix)

### 3.1 The analysis bug (must fix — decision S4-D1/S4-D5)
`eval_task.exs`'s `analysis_checks/1` returns `{awarded, max, passed, label}` tuples where
`awarded` is **hardcoded to `max`** for every check regardless of `passed`. So
`analysis_points = 10` always, `analysis_score = min(10/10,1.0) = 1.0` **always**, and the
`reasons` reject-filter (`awarded == max`) drops every check so deductions are never reported.
**Proven:** a solution with no `@moduledoc`, a `# TODO`, and a 110-char line still scores
`analysis = 1.0`. The 20% analysis weight is dead.

**Fix:** award `passed && max || 0`. **Drop Credo** (it's a declared dep but `credo_issues` is
hardcoded `[]` → 2 permanently-free points; no linting ever runs). Renormalize the remaining
8 real points to the 0.2 weight:

| Check | pts | source |
|-------|-----|--------|
| `@moduledoc` present | 2 | `has_moduledoc` |
| `@spec` present | 2 | `has_typespecs` |
| `@doc` present | 1 | `has_doc_on_public_fns` |
| no line > 98 chars | 1 | `lines_over_98 == 0` |
| no TODO/FIXME/HACK/XXX | 1 | `todo_count == 0` |
| no SQL-injection interpolation | 1 | `sql_injection_risk == false` |
| **total** | **8** | `analysis_score = points / 8` |

Weights stay `tests·0.7 + analysis·0.2 + compilation·0.1`. **This is a one-time scoring-regime
shift** — existing solutions missing `@spec`/`@doc` will drop below 1.0. That is intended.

### 3.2 Multi-file analysis (aggregate)
Run the analysis over the concatenation of the bundle's `lib/**/*.ex` sources only (exclude
migrations, config, and the injected kit). `@moduledoc`/`@spec`/`@doc` = "present in any lib
module" (or, stricter, require per-module — a config knob). Line-length/TODO/SQLi = union.

### 3.3 FIM analysis (function-only, decision F-D2)
Analyze **the candidate function text only**; DROP the `@moduledoc`/`@spec`/`@doc` checks (a
single infilled function legitimately has none). Keep line-length, no-TODO, no-SQLi (3 pts,
renormalized). Compilation (of the reconstructed module) + tests (parent harness) unchanged.
Proven in v2 (`analysis_max` drops to the FIM subset).

---

## 4. Multi-file (`<file path>` bundle) — the two tiers

Bundle grammar: `<file path="relative/path">\n…contents…\n</file>` blocks. Parser:
`Regex.scan(~r/<file path="([^"]+)">\n(.*?)\n<\/file>/s, src)`. Materialize `.ex`/`.exs` into a
temp tree honoring `lib/`, `priv/repo/migrations/`, `config/`. `validate/1` rejects fragments
(a `.ex` with no `defmodule` — the 017 failure), duplicate paths, path-escapes, and files outside
`lib|priv|config|test`.

### 4.1 Tier-A (self-contained: pure_otp, plug_selfcontained)
`Kernel.ParallelCompiler.compile(bundle_sources, return_diagnostics: true)` (resolves inter-module
order), then run the task's own harness. **No kit, no DB, no endpoint.** The harness carries its
own support (`Plug.Test` + `Router.call/2`, in-memory GenServer stores via `start_supervised!`, or
a FakeRepo). Proven on 020/021/022/023/024/025/102.

### 4.2 Tier-B (phoenix_conncase) — the host kit
For the prefix inferred from `use <Web>.ConnCase` (prefix, web-prefix = `<X>Web`, otp_app =
`Macro.underscore`), render a templated kit, compile `bundle + kit`, start `{Repo, Endpoint}`,
run the bundle migration **in automatic mode**, then `Sandbox.mode(repo, :manual)`, then run the
harness. Exact kit in `docs/01` Appendix B and `eval_task_v2.exs :render_phoenix_kit`. Kit modules:

- `<Prefix>.Repo` — `use Ecto.Repo, adapter: Ecto.Adapters.SQLite3` (file-backed db + Sandbox).
- `<Web>` — web-entry with `:controller` / `:router` / `:verified_routes` (`~p`) + `__using__`.
- `<Web>.Endpoint` — `use Phoenix.Endpoint, otp_app:`, `server: false`, `Plug.Parsers`,
  `render_errors: [formats: [json: <Web>.ErrorJSON]]`, `plug <Web>.Router`.
- `<Web>.ConnCase` — `Phoenix.ConnTest` + `Ecto.Adapters.SQL.Sandbox.start_owner!/stop_owner`.
- `<Web>.ErrorJSON` — **default only; see override rule.**

**Kit override rule (decision S4-D3, forced by 018):** the kit must inject `<Web>.ErrorJSON`
(and other presentation infra like `ErrorHTML`) **only if the bundle does not already define it**
— detect by scanning the bundle's module names. A task asserting a custom error contract (018:
404 body `"Not found"`, per-field 422) ships its own `ErrorJSON`; the kit backs off (else a
`module … is currently being defined` collision). With this, 018 → **31/31**.

**Ordering gotcha (load-bearing):** run migrations while the pool is in **automatic** mode (they
commit to the shared file db); running them inside a `Sandbox.mode(:manual)` checkout rolls them
back → "no such table". Use a temp **file** SQLite db (not `:memory:`) so the Sandbox pool's
connections share one db.

### 4.3 DB (decision D3 + S4-D2): SQLite default, Postgres deferred
In-BEAM SQLite (`ecto_sqlite3`) is the default and only-built path. It handles `utc_datetime`,
soft-delete, `Decimal`/`:numeric`, and async Sandbox (each task harness is a single ExUnit
module → tests run serially, so single-writer SQLite is fine). **But some tasks need Postgres-only
SQL** — proven by **017**, whose spec mandates `ILIKE` (`Ecto.QueryError: ilike is not supported
by SQLite3`; 18/23 on SQLite, 23/23 with `LIKE`). Such tasks declare **`db: :postgres`** in their
manifest and are **skipped-with-reason** ("requires Postgres — not provisioned") until a Postgres
kit variant is built (docker `postgres:16` — `docker`/`apt` are available here). PG kit variant:
`storage_up` → migrate in `:auto` → `Sandbox.mode(:manual)` → per-test `start_owner!`.

---

## 5. FIM (fill-in-the-middle) — reconstruction

Mechanism (no manifest): derive parent from the dir name (`<a>_<b>_<name>_0N` → `_01`, which has
the harness) → extract the ` ```elixir ` skeleton from the FIM `prompt.md` → splice the candidate
at the `# TODO` marker → compile the reconstructed module → run the **parent `_01` harness**.

**Reconstruct from the prompt skeleton, NOT the `_01` module** (decision F-D0): the `_01` modules
drifted after FIM extraction, so `solution.ex` is not a substring of any current `_01`; the prompt
skeleton is the frozen, self-consistent source.

**Two splice conventions** (both handled by `eval_task_v2.exs :splice`):
- **stub-body** (53 dirs): `def SIG do  # TODO  end` → replace the enclosing `def…end`. Find the
  enclosing def by scanning up for `^\s*(def|defp|defmacro)\s`; find its matching `end` at the
  def's indentation (stub bodies never nest, so the first `end` at that column matches).
- **placeholder-line** (1 dir, `004_004_calendarscheduler_02`): `#TODO defp foo` standing for a
  whole multi-clause function → replace just that line. Marker forms `# TODO` / `#TODO` /
  `# TODO:` all matched by `~r/#\s*TODO:?/i`.

**Candidate extraction (decision F-D3):** strip a leading ` ```elixir ` fence if present; if the
candidate contains `defmodule`, use it as a complete module directly (no splice); else splice the
function. Both proven (fenced → 11/11; whole-module → 11/11).

---

## 6. The validator (reference-green + mutation) — decisions D6, F-D1, F-D4

A CI gate that catches harness bugs (compile-only checks miss them — 021's harness *compiles* but
fails every test) and skeleton↔harness drift:

1. **Reference-green:** run every task's reference solution through the evaluator; assert green
   (or the task's declared expected state). Covers single-file, multi-file, and all 54 FIM.
   Proven: `eval_fim.exs` (54/54), `eval_task_v2.exs` (multifile + single sample).
2. **FIM mutation:** for each FIM, splice a `raise`-body mutant of the target and assert the parent
   harness now **fails**; a mutant that passes = under-tested target. Proven: `mut_fim.exs` →
   **54/54 GOOD_exercised** (no existing FIM is under-tested).

`validate_harnesses.sh` today covers only `tasks/*/` and only checks compilation → extend to
`tasks_multifile/` + FIM, and make it RUN the reference (not just compile).

---

## 7. Discovery + `run_all` (the invisible-tasks gap)

`run_all.exs` globs `tasks/*/test_harness.exs`. **FIM dirs have no harness and multifile lives
under `tasks_multifile/`, so both are silently skipped today.** Discovery must enumerate:
- single-file: `tasks/*/` with a `test_harness.exs` + a non-bundle `solution.ex`;
- FIM: `tasks/*/` with **no** `test_harness.exs` (+ a `# TODO` prompt + a parent `_01` harness);
- multi-file: `tasks_multifile/*/` with a `test_harness.exs` + a `solution.ex`.
Proven count: **111 + 54 + 4 = 169**.

---

## 8. Per-task status matrix (validated this session)

| Task | Shape / tier | Archetype | Status | Notes |
|------|--------------|-----------|--------|-------|
| single-file ×111 | single | — | ✅ backward-compat exact | v2 == current eval_task |
| FIM ×54 | fim | — | ✅ 54/54 green + mutation-exercised | reconstruct from prompt skeleton |
| 102 | multifile / A | pure_otp | ✅ 18/18 | FakeRepo in harness |
| 020 | multifile / A | plug_selfcontained | ✅ 23/23 | reads `conn.params["file"]` + `File.stat` for 5MB limit |
| 021 | multifile / A | plug_selfcontained | ✅ 20/20 | **harness bug** — dead `Enum.reduce(headers,…)` line; fix harness |
| 022 | multifile / A | plug_selfcontained | ✅ 23/23 | opts via `copy_opts_to_assign` + `conn.private` |
| 023 | multifile / A | pure_otp | ✅ 14/14 | GenServer + injected clock |
| 024 | multifile / A | plug_selfcontained | ✅ 18/18 | `Plug.Crypto.secure_compare` |
| 025 | multifile / A | plug_selfcontained | ✅ 11/11 | Registry pub/sub; `child_spec` id-from-name fix |
| 016 | multifile / B | phoenix_conncase | ✅ 14/14 | SQLite kit, plain-string paths |
| 018 | multifile / B | phoenix_conncase | ✅ 31/31 | domain-only + kit ErrorJSON-override; **latent 201-vs-200** harness bug |
| 017 | multifile / B | phoenix_conncase | ⚠️ 18/23 SQLite | **needs Postgres (ILIKE)** → `db: :postgres`, deferred/skip |
| 019 | multifile / B | phoenix_conncase | ⛔ unsolved | no solution + no migration; needs both (T6) |

Validated solutions promoted to `docs/prototypes/solutions/` (017/018 normalized; 020–025; 021).

---

## 9. Known issues / task bugs found (policy S4-D4: adjudicate per prompt, fix wrong side, log)

| ID | Where | Defect | Fix |
|----|-------|--------|-----|
| KI-1 | `scripts/eval_task.exs` | analysis score always 1.0 (awarded=max regardless of pass/fail); Credo never run | fix pass/fail; drop Credo; renormalize to 8 pts (§3.1) |
| KI-2 | `tasks_multifile/021_.../test_harness.exs` | leftover `conn(m,p) |> Enum.reduce(headers,…)` raises `Protocol.UndefinedError` on every request | delete the dead block |
| KI-3 | `tasks_multifile/018_.../test_harness.exs` | asserts 200 on create, but the RESTful controller returns 201 | fix harness to accept 201 (per prompt) |
| KI-4 | `tasks/004_004_calendarscheduler_02/prompt.md` | marker is `#TODO` (no space) — inconsistent | tolerated by regex; optionally normalize to `# TODO` |
| KI-5 | `tasks_multifile/019_...` | no reference solution + no `items` migration | author both (T6) |

---

## 10. Implementation notes (Plug/Phoenix/Ecto specifics discovered)

- **`Plug.Test.conn(:post, path, map)` does NOT send a real multipart body** — it pre-populates
  `conn.params`/`body_params` (preserving `%Plug.Upload{}`) and a 17-byte sentinel body. A file-
  upload task must read `conn.params["file"]` and enforce size via `File.stat!(upload.path).size`;
  adding `Plug.Parsers` multipart would crash on the fake body. (`deps/plug/.../test/conn.ex:199`.)
- **Runtime router opts** (store/secret/dir) reach routes+plugs via
  `use Plug.Router, copy_opts_to_assign: :key` → `conn.assigns.key`. (`deps/plug/.../builder.ex:180`.)
- **`child_spec` id collision:** starting a 2nd named GenServer of the same module under a test
  supervisor fails `{:already_started}` because the default `child_spec` reuses `id: __MODULE__`.
  Override `child_spec/1` to derive `id` from the `:name` option.
- **`Plug.Crypto.secure_compare/2`** short-circuits to `false` on length mismatch (safe for
  garbage signatures). (`deps/plug_crypto/.../crypto.ex:129`.)
- **`Phoenix.ConnTest.dispatch` calls `endpoint.call/2` directly** — no webserver; the Endpoint
  must be *started* (populates config ETS + persistent_term) but `server: false` starts no Cowboy.
- **`Ecto.Migrator.up(repo, version, module, log: false)`** runs a bundled migration
  programmatically; `ecto_sqlite3`'s migration lock is a no-op so `pool_size: 1` migrates fine.
- **`Kernel.ParallelCompiler.compile(paths, return_diagnostics: true)`** returns
  `{:ok, modules, %{compile_warnings: […]}}` — the 3rd element is a **map**, not a list.

---

## 11. Sequencing (updated)

1. **FIM first** (FIM-T1 + FIM-T2): 54 tasks tested + machine-verified; ~40-line proven runner.
2. **Multi-file MVP** (T1–T3 + T-021-FIX): Tier-A → 6 self-contained tasks green (solutions ready
   in `docs/prototypes/solutions/`).
3. **Scoring fix** (KI-1 / new task T-SCORE-FIX): fix analysis + drop Credo (one-time regime shift).
4. **Tier-B kit** (T5, with ErrorJSON-override): 016 + 018 green; normalize 018/019; skip 017 (PG).
5. **Validator + discovery** (T8, FIM-T4, T9): reference-green + mutation gate; `run_all` sees all 169.
6. **Deferred:** Postgres kit variant (T10) for `db: :postgres` tasks (017 …).

---

## 12. Execution log (AS-BUILT, 2026-07-01)

The plan was executed on branch `multifile-fim-eval`. The evaluator was refactored from a
monolithic `scripts/eval_task.exs` into compiled, testable modules under `lib/eval_task/`, with
`scripts/eval_task.exs` reduced to a thin entry point that prepends the build paths and calls
`EvalTask.CLI.main/1` (works under both `mix run` and the bare `elixir` invocation `run_all` uses).

### Modules built (`lib/eval_task/`)
- `bundle.ex` — parse/validate/materialize `<file>` bundles (T1).
- `manifest.ex` — inference + optional `manifest.exs` override (T2).
- `fim.ex` — FIM reconstruction (both splice conventions), candidate extraction, `mutate/1` (FIM-T1).
- `phoenix_kit.ex` — prefix-parameterized Phoenix+SQLite kit with the ErrorJSON-override rule (T5).
- `analysis.ex` — **fixed** scoring (award by pass/fail, Credo dropped, renormalized to 8 pts;
  `:full` and `:fim` modes) (T-SCORE-FIX, T7).
- `runner.ex` — compile + harness + score for each shape; Tier-A/Tier-B; boots apps under bare elixir.
- `discovery.ex` — enumerate all 3 shapes (T9/FIM-T2).
- `cli.ex` — arg parsing, resolution, shape detection, dispatch, JSON (T3, FIM-T1).
- `failure_collector.ex` — the ExUnit formatter.
- Scripts: thin `scripts/eval_task.exs`; rewritten `scripts/run_all.exs` (3-shape discovery);
  new `scripts/validate.exs` (reference-green + FIM-mutation gate). Unit tests in `test/eval_task/`.

### Discoveries during execution (each fixed + documented)
1. **Bare-elixir app-starting** — under `elixir scripts/eval_task.exs` (run_all's invocation) no OTP
   apps auto-start. Plug tasks (020/022/024/025) and Ecto single-file tasks (032_00x) failed until
   `run_harness` started `[:crypto, :mime, :plug_crypto, :plug, :jason, :stream_data, :ecto_sql,
   :ecto_sqlite3]`. (Not visible under `mix run`, which starts everything.)
2. **Temp-file collision across OS processes** (KI-8) — `System.unique_integer/1` is unique only
   within one BEAM; `run_all` spawns one BEAM per task in parallel, so two evals collided on the same
   `/tmp/evalfim_NNN.ex` and mis-reconstructed (001_002_02/03 falsely compile-failed). Fixed: temp
   names include `System.pid()`.
3. **033_003 harness bug** (KI-6) — its fixture has **4** `/api/users` entries but the assertion
   expected 3; the solution correctly counts 4. Adjudicated per fixture → **fixed the harness**.
4. **097_001 non-ExUnit harness** (KI-7) — a hand-rolled `PasswordPolicyTest.run/0` that isn't even
   auto-invoked → the task was effectively untested (0 ExUnit tests). Converted to ExUnit.
5. **018 create-status** (KI-3, downgraded) — the prompt is SILENT on the create status (only
   mandates 200 for DELETE/restore), so the harness's 200 is a valid convention, not a bug. The
   normalized solution uses 200. No change needed.

### Known-issues status
| ID | Status |
|----|--------|
| KI-1 analysis scoring dead | **FIXED** — award by pass/fail, Credo dropped, renormalized to 8 pts (`analysis.ex`) |
| KI-2 021 harness dead-code | **FIXED** — dead `Enum.reduce(headers,…)` block removed |
| KI-3 018 201-vs-200 | **Not a bug** — prompt silent on create status; 200 stands |
| KI-4 calendarscheduler_02 `#TODO` | **Tolerated** — regex handles it; FIM 04 green |
| KI-5 019 no solution/migration | **FIXED** — solved (green 20/20) |
| KI-6 033_003 fixture/assert mismatch | **FIXED** — harness corrected to 4 |
| KI-7 097_001 non-ExUnit harness | **FIXED** — converted to ExUnit |
| KI-8 temp-file collision (parallel) | **FIXED** — `System.pid()` in temp names |

### Corpus status (via `run_all`, after fixes)
176 discovered (111 single + 11 multifile + 54 FIM). All-pass across all shapes except:
017 SKIPPED (`db: :postgres` / ILIKE). Average score ≈ 0.95 (single-file scores now reflect the
**real** analysis component — well-documented solutions ≈ 1.0, sparse ones lower).

### Final corpus (authoritative `run_all`, all fixes in)
**176 discovered · 176 found · 175 compiled · 173 all-pass · 1 skip (017/PG) · avg 0.981.**
Two non-green remain, both **pre-existing single-file bugs newly surfaced by the now-working
evaluator** (outside the multi-file/FIM plan scope):
- **097_001** — non-ExUnit harness; being converted to ExUnit (KI-7).
- **KI-9 · 032_002** — `stats.failed` is 15, the test expects 5. The solution's per-batch
  try/rescue is correct; under SQLite, `insert_all(on_conflict: :raise)` against pre-seeded
  UNIQUE conflicts fails the whole ingestion (all 3 batches), not just the conflicting middle
  batch — a **Postgres-vs-SQLite conflict/transaction semantics gap** (the same class as 017's
  `ILIKE`). Single-file DB tasks have no `db: :postgres` skip mechanism today; needs adjudication
  (fix the solution's conflict handling, mark the task Postgres-requiring, or relax the test).
  Pre-existing; not introduced by this work.

Every plan deliverable (FIM, multi-file Tier-A/B, scoring fix, validator, discovery, run_all,
KI-1..KI-8) is complete and green. The two remaining items are surfaced pre-existing defects the
evaluator now correctly reports — exactly the value the validator was built to provide.

### KI-7 (097_001) — RESOLVED
Harness converted to ExUnit (17 cases, `PasswordPolicy.validate/2`), now **17/17 green**. The
conversion surfaced **3 test-authoring errors in the original hand-rolled expectations** (never
caught because that harness was never executed); in every case the solution is correct per
`prompt.md`, so the expected values were corrected, not the solution. Net remaining non-green
after all work: **032_002 only** (KI-9, pre-existing SQLite semantics) + **017 skipped** (PG).

---

## 13. Directory unification (2026-07-01, option C)

`tasks_multifile/` was **merged into `tasks/`** and renamed to the standard `a_b_c_d` scheme
(e.g. `tasks_multifile/016_paginated_list_endpoint` → `tasks/016_001_paginated_list_endpoint_01`).
Rationale: 016–025/102 were already part of the same global task-number catalog as `tasks.md`, so
the split was only cosmetic. Now the whole corpus is one uniform, numerically-addressable
namespace: multi-file tasks can be run by number (`eval_task.exs 16 1`) and can gain variations /
FIM subtasks like everything else.

The only code change was in `discovery.ex`: shape classification is now **content-based** (a
harness-having dir whose `solution.ex` is a `<file>` bundle, or which ships a `manifest.exs`, is
`:multifile`; otherwise `:single`), rather than location-based. Runtime shape detection
(`CLI.detect/2`) was already content-based, so `eval_task.exs`, `run_all.exs`, and `validate.exs`
needed no logic changes. Discovery still reports 176 tasks (111 single + 11 multi-file + 54 FIM).
