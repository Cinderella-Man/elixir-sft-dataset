# 01 — Enabling Multi-File Task Support with Automated Testing

**Status:** Reviewed & decisions locked (design review 2026-07-01). **Date:** 2026-07-01.
**Author:** investigation + prototyping session (see Appendix A for runnable prototypes).
**Scope:** How to let a task's reference/candidate solution span multiple files
(controller + schema + migration + context + router + …) while keeping the project's
defining property — *every solution is automatically compiled and tested in an isolated
BEAM and scored* — intact.

> **Update (post design review):** The 7 open questions in §11 were resolved and the plan was
> stress-tested with an integrated evaluator prototype (all 3 archetypes green; several claims
> corrected — Postgres is unavailable here, 018 hardcodes Postgres, and task 021's harness is
> broken). See **`docs/02-multifile-task-breakdown.md`** for the locked decisions, the
> stress-test corrections, and the ordered implementation backlog. Runnable prototypes promoted
> to **`docs/prototypes/`**. The chosen design: extend `eval_task.exs` in-process (B1);
> inference-first config + optional `manifest.exs`; SQLite default (normalize 018, Postgres
> deferred); domain-only bundles with a kit-owned Phoenix host; per-task prefix substitution;
> a reference-solution-green CI gate.
>
> **FIM (fill-in-the-middle) auto-testing** — a separate, second requirement — was also designed,
> prototyped, and validated (all 54 existing FIM subtasks reconstruct + pass their parent harness;
> 54/54 mutation-exercised). It is **independent of multi-file and shippable first**. See
> `docs/02` §F for the FIM decisions, mechanism, and task backlog; `docs/prototypes/eval_fim.exs`
> + `mut_fim.exs` for the runnable proofs.

---

## 1. Executive summary

Multi-file support is **feasible today with modest, well-bounded changes**, and I proved
the two hardest paths end-to-end against the *real* existing tasks (Appendix A):

- **Task 102** (pure OTP + Ecto schema, self-contained harness): **18/18 tests pass** using
  nothing but a multi-module compile step — *zero* new infrastructure.
- **Task 016** (Phoenix controller + Ecto schema + migration + `ConnCase`): **14/14 tests
  pass** headless, driving the *unmodified* harness against the *real* solution bundle plus a
  generic, prefix-parameterized "host kit" (Repo + Endpoint + web-entry + ConnCase + ErrorJSON),
  an in-process SQLite database, and the bundle's *real* migration run via `Ecto.Migrator`.

The recommended design is a **two-tier evaluator** keyed off a tiny per-task manifest:

- **Tier A — self-contained** (`pure_otp`, `plug_selfcontained`, `ecto_only` with an inline
  Repo/FakeRepo): the only new machinery is a **bundle unpacker** that parses the
  `<file path="…">…</file>` blocks and compiles every module with
  `Kernel.ParallelCompiler.compile/2` before running the harness. 7 of the 11 existing
  multifile tasks fall here.
- **Tier B — framework host kit** (`phoenix_conncase`): additionally inject a small,
  **prefix-parameterized Phoenix+Ecto scaffold** (Endpoint started with `server: false`,
  web-entry module, `ConnCase`, Repo on file-backed SQLite, a programmatic migration runner)
  through the evaluator's *existing* `compile_support/1` hook. 4 of the 11 tasks.

Two cross-cutting requirements make this robust:
1. An **authoring/normalization contract**: every emitted file must be a *complete, compilable
   module at a canonical path*. (Task 017 currently ships a router *fragment* and is therefore
   un-testable as authored — see §4.4 and §9.6.)
2. **One OS process per task** (already true in `run_all.exs`) so tasks that reuse module
   prefixes (017 & 019 both use `MyApp`) can't collide.

Everything below is grounded in either dep-source reading (cited) or the runnable prototypes
in Appendix A.

---

## 2. Problem statement — why multi-file was avoided

The project's value proposition (`README.md`) is: *"A framework for evaluating AI-generated
Elixir code against verified test harnesses. Each solution runs in its own BEAM process — a
non-compiling solution cannot affect any other task's evaluation."* The evaluator
(`scripts/eval_task.exs`) hard-assumes **one solution file**:

- `resolve_task_args/3` globs `tasks/#{a}_#{b}_*_#{d}` — only the `tasks/` tree, only the
  `NNN_NNN_*_NN` single-file naming (doesn't even match `016_paginated_list_endpoint`)
  (`eval_task.exs:208-210`).
- `source = File.read!(solution_file)` then `compile_solution/1` →
  `Code.compile_file(path)` — a single file (`eval_task.exs:112-114, 261-264`).
- `analyze_source/1` runs its quality regex over that **one** file's text
  (`eval_task.exs:359-377`).
- `run_all.exs` globs `tasks/*/test_harness.exs` and `Path.join(task_dir, solution_filename)`
  — one solution path per dir (`run_all.exs:114, 118`).

Real backend work (a Phoenix endpoint, an Ecto ingestion, a persisted state machine) is
inherently multi-module: schema + migration + context + controller + router, plus the
test-support glue (`ConnCase`, `Endpoint`, `Repo`, sandbox) that a normal `mix phx.new` app
provides. Bundling all of that into one `solution.ex` and compiling it with a single
`Code.compile_file/1` **raises immediately** (the `<file>` bundle isn't valid Elixir), and the
harnesses reference app modules that don't exist in the eval environment. So multi-file tasks
were parked in `tasks_multifile/` (4 solved, 7 unsolved) and left out of the automated pipeline.

**The good news:** the maintainer already chose a multi-file interchange format
(`<file path="…">…</file>`), the root `mix.exs` already depends on everything needed
(ecto_sql, **ecto_sqlite3**, postgrex, phoenix, plug, jason, decimal, …), and the evaluator
already has an unused extension seam — `compile_support/1` (`eval_task.exs:235-248`), which
`run_all.exs` already feeds `"test/support"` (`run_all.exs:166-172`). We are extending an
existing design, not inventing one.

---

## 3. What was validated (prototype ledger)

All run against this repo's compiled deps (Elixir 1.19.5 / OTP 28). Full scripts in Appendix A.

| # | Claim under test | Result |
|---|---|---|
| 1 | Multi-module bundle compiles regardless of file order (`Kernel.ParallelCompiler.compile/2` resolves inter-module deps) | ✅ `[A,B]`, B references A defined "later" |
| 2 | Headless Ecto + in-memory SQLite + **real migration** via `Ecto.Migrator.up/4`, then insert/query | ✅ count=3 |
| 3 | Minimal real Phoenix `Endpoint` (`server: false`) + `Phoenix.ConnTest` + programmatic `ExUnit.run()` | ✅ 1/1 |
| 4 | **Capstone**: real `tasks_multifile/016` harness vs real bundle + generic host kit + SQLite + bundle migration | ✅ **14/14** |
| 5 | Self-contained real `tasks_multifile/102` (FakeRepo) with only bundle compilation, no kit | ✅ **18/18** |
| 6 | Extended capstone `017` (`~p` verified routes + JSON view + Decimal) | ❌ *fails to compile* — its `router.ex` is a fragment, not a module (see §4.4). Demonstrates the authoring contract. |

**Gotchas discovered (must be encoded in the design):**
- Run migrations while the pool is in **automatic** mode (they commit); running them inside a
  `Sandbox.mode(:manual)` checkout **rolls them back** → "no such table". Order: start repo →
  migrate → `Sandbox.mode(repo, :manual)`.
- Use a **temp file** SQLite DB (`/tmp/x.db`) for Tier-B so the Sandbox connection pool shares
  one database; `:memory:` is per-connection.
- The host-kit Endpoint needs `render_errors: [formats: [json: <Web>.ErrorJSON], layout: false]`
  + an `ErrorJSON` module, else a raised action 500s into a missing `ErrorView`.
- Bundle modules must be compiled as **separate files** (a struct defined and used in the same
  `.exs` fails with "struct not yet defined in same context"); the real flow does this anyway.
- `use Phoenix.ConnTest` is deprecated in 1.8 (warning only) → prefer
  `import Plug.Conn; import Phoenix.ConnTest`.
- `async: true` is safe with SQLite here: ExUnit `async` only parallelizes across *different*
  test modules, and each task harness is a *single* module, so its tests run serially. (Still,
  normalizing DB-backed harnesses to `async: false` is the conservative choice; the SQLite
  adapter formally documents no-async-under-Sandbox — `deps/ecto_sqlite3/…/sqlite3.ex:130-135`.)

---

## 4. The task taxonomy (grounding)

The 11 `tasks_multifile/` tasks split into **3 archetypes**. This split drives the whole design.

### 4.1 Manifest table

| # | Task | Archetype | Prefix(es) | Host-kit glue the bundle omits | DB | Migration in bundle | async | Solved | tests |
|---|------|-----------|-----------|-------------------------------|----|--------------------|-------|--------|-------|
| 016 | paginated_list | `phoenix_conncase` | `PaginatedList`/`Web` | ConnCase, Endpoint, Repo, web-entry, Sandbox | real | ✅ | true | ✅ | 14 |
| 017 | search_filter_sort | `phoenix_conncase` | `MyApp`/`Web` (`~p`) | ConnCase, Endpoint, Repo, web-entry, **full Router** (bundle ships a fragment) | real | ✅ | true | ✅ | 23 |
| 018 | crud_soft_delete | `phoenix_conncase` | `SoftCrud`/`Web` (`~p`) | **only** ConnCase + Sandbox + boot (bundle is a near-complete app) | real (PG) | ✅ | true | ✅ | 31 |
| 019 | bulk_create | `phoenix_conncase` | `MyApp`/`Web` | ConnCase, Endpoint, Repo, web-entry, Router, **+ migration (none shipped)** | real | ❌ none | true | ❌ | 20 |
| 020 | file_upload | `plug_selfcontained` | `FileUpload` | none (Plug.Test + own Store) | no | – | false | ❌ | 23 |
| 021 | versioned_api | `plug_selfcontained` | `VersionedApi` | none | no | – | true | ❌ | 20 |
| 022 | nested_resource_authz | `plug_selfcontained` | `TeamRouter`/`TeamStore`/`AuthPlug` | none | no | – | false | ❌ | 23 |
| 023 | idempotent_post | `pure_otp` (misnamed; no HTTP) | `IdempotentPayments` | none (own Clock) | no | – | false | ❌ | 14 |
| 024 | webhook_signature | `plug_selfcontained` | `WebhookReceiver` | none (Plug.Test + MemoryStore) | no | – | true | ❌ | 18 |
| 025 | long_polling | `plug_selfcontained` | `Notifications`/`Poller`/`Router` | none | no | – | false | ❌ | 11 |
| 102 | genserver_state_machine | `pure_otp` (+ecto lib) | `StateMachine`/`EntityTransition` | none (own FakeRepo) | no (FakeRepo) | present, unused | false | ✅ | 18 |

### 4.2 Archetype → machinery required

- **`pure_otp`** (023, 102): bundle unpacker + `ExUnit.run()`. 102 also needs the `ecto`
  *library* on the code path (already a root dep) for its schema/query structs; **no Repo/DB
  started** (FakeRepo is in the harness).
- **`plug_selfcontained`** (020, 021, 022, 024, 025): bundle unpacker + `plug` on path
  (already a dep). Harness carries all support (`use Plug.Test`, `Router.call(conn,
  Router.init(opts))`, in-memory GenServer stores via `start_supervised!`). No Endpoint, no
  ConnCase, no Repo, no migrations.
- **`phoenix_conncase`** (016, 017, 018, 019): the heavy tier — a **prefix-parameterized
  host kit**: `<Prefix>.Repo`, `<Prefix>Web.Endpoint` (`server: false`), `<Prefix>Web`
  web-entry (`:controller`/`:router`/`:verified_routes`), `<Prefix>Web.ConnCase` (wraps
  `Phoenix.ConnTest` + `Ecto.Adapters.SQL.Sandbox`), `<Prefix>Web.ErrorJSON`, a **migration
  runner**, and app-boot ordering.

### 4.3 The prefix-collision constraint
017 and 019 both use `MyApp`/`MyAppWeb`; 016/017/018/019 each define `<Prefix>.Repo`,
`<Prefix>Web.Endpoint`, `<Prefix>Web.ConnCase`. These are global module names, so **every task
must run in its own OS process** (fresh BEAM). `run_all.exs` already shells out one
`System.cmd("elixir", …)` per task (`run_all.exs:174`), so this holds today; any future
*in-process* batch runner would collide and must be avoided (or the kit must rename modules).

### 4.4 The authoring-contract problem (why 017 fails)
016 and 018 ship complete, compilable router modules; **017 ships a router *fragment*** —
`lib/my_app_web/router.ex` literally begins `# Add inside your existing :api scope:` followed
by a bare `scope "/api" … end` with no `defmodule … use MyAppWeb, :router`. It cannot compile
standalone (`error: undefined function scope/3`). 019 ships *no* migration though its tests
need an `items` table. The bundles are **inconsistent**: some are whole apps (018), some
domain-only (016), some fragments (017). **Enabling autotest therefore requires an authoring
contract** (§9.6): every file is a complete module at a canonical path; required infra files
(migration, routes) are either present-and-complete or supplied by the kit — never a prose
snippet.

---

## 5. The bundle interchange format

The repo already standardizes on **XML-ish `<file path="relative/path.ex">…</file>` blocks**,
used by all 4 solved multifile solutions. Keep it. It is:
- trivially parseable: `Regex.scan(~r/<file path="([^"]+)">\n(.*?)\n<\/file>/s, text)` (proven);
- path-carrying (so we know `lib/` vs `priv/repo/migrations/` vs `config/`);
- natural for a model to emit and for a prompt to request ("give me all modules in separate
  files").

Alternatives considered and rejected as the *primary* format (kept as notes in §7.1): fenced
code blocks with a path comment (ambiguous parsing), unified diffs/patches (great for
edit-tasks à la SWE-bench, wrong for from-scratch generation), a JSON `{path: content}` map
(escaping noise, worse for the model to emit). **Decision: keep `<file>` blocks; formalize them
with a strict grammar and a validator** (§9.1).

---

## 6. Current evaluator — exactly what changes

Minimal-surface plan that preserves the isolation guarantee:

1. **Detection.** In `eval_task.exs`, if `solution_file` begins with `<file` (or the task
   manifest says `multifile: true`), route to a new `compile_bundle/1` instead of
   `compile_solution/1`.
2. **`compile_bundle/1`.** Parse blocks → materialize `.ex`/`.exs` into a temp tree →
   `Kernel.ParallelCompiler.compile(source_paths, return_diagnostics: true)`; collect
   `{:ok, modules, warnings}` (map warnings/errors into the same shape `compile_solution/1`
   returns so scoring is unchanged). Migrations (`.exs` under `…/migrations/`) are compiled
   separately and handed to the kit, not counted as solution warnings.
3. **Support kit.** Reuse `compile_support/1` (already compiles `support_dir/**/*.ex`) to load
   the host kit for Tier-B tasks. The kit is *rendered per task* from the manifest's prefix
   before compilation.
4. **Analysis over many files.** `analyze_source/1` currently takes one source string; change
   the caller to pass the **concatenation** of the bundle's source files (or aggregate
   per-file metrics — see §10). Line-length / moduledoc / spec / TODO checks then span the
   whole solution.
5. **Task resolution.** Add a resolver branch for `tasks_multifile/<name>/` (flat dirs, no
   `a_b_c_d`), and teach `run_all.exs` to also glob `tasks_multifile/*/test_harness.exs`.
6. **Everything else is unchanged**: ExUnit still runs programmatically via the
   `FailureCollector` formatter; scoring weights (tests·0.7 + analysis·0.2 + compile·0.1) are
   untouched; one OS process per task still holds.

---

## 7. Design options (the full menu)

Five independent decision axes. The recommendation (§8) picks one option per axis, but all are
laid out so the tradeoffs are explicit.

### 7.1 Axis A — file interchange format
| Option | Pros | Cons |
|---|---|---|
| **A1. `<file path>` blocks** *(current, recommended)* | already used; path-aware; easy regex; natural model output | bespoke; needs a validator |
| A2. Fenced blocks w/ ```` ```elixir path=lib/x.ex ```` header | familiar to models | non-standard header, brittle parsing, path ambiguity |
| A3. Unified diff / patch | perfect for *edit* tasks; SWE-bench-style | wrong for from-scratch; needs a base tree |
| A4. JSON `{ "files": {path: content} }` | unambiguous; machine-first | escaping hell; models emit it worse; ugly in `solution.ex` |

### 7.2 Axis B — execution / isolation model
| Option | Pros | Cons |
|---|---|---|
| **B1. In-BEAM multi-module compile** *(recommended)* | fastest; matches current design; no toolchain; proven (Appendix A) | modules live in one global namespace → one-proc-per-task; long-running procs leak atoms/ETS (mitigated by per-task OS process) |
| B2. Ephemeral generated mix project per eval (`mix test`) | maximal fidelity (real config, `~p`, ecto tasks); mirrors real dev | slow (deps/compile per run or a warm cache); heavier; more moving parts |
| B3. Container per task (SWE-bench-style) | hermetic; language-agnostic; safest for untrusted code | infra-heavy; slowest; overkill for a curated dataset |
| B4. `Mix.install/2` self-contained script | one-file portability | re-resolves deps; slow; redundant with the project's own deps |

### 7.3 Axis C — database
| Option | Pros | Cons |
|---|---|---|
| **C1. SQLite `:memory:` + `pool_size:1`, no Sandbox, `delete_all` reset** *(recommended default; what the 032 family already does)* | zero external service; perfect per-BEAM isolation; migration lock is a no-op in ecto_sqlite3 so pool_size 1 migrates fine | single writer ⇒ effectively `async:false`; limited SQL; `:memory:` dies with the process |
| **C2. SQLite temp **file** + Sandbox** *(recommended for Tier-B ConnCase)* | pooled connections share one DB; sandbox rollback per test; proven in the 016 capstone | still one writer (serial); temp file cleanup |
| C3. Postgres, per-eval DB + Sandbox | full fidelity (JSONB, upserts, real FKs); true async ConnCase | needs a running server; per-eval create/drop lifecycle can leak/fail; reintroduces a shared external dep |
| C4. Hand-written FakeRepo shim (102) | no DB at all; fully deterministic | only mimics the Repo API the solution happens to use; brittle to query shape |

### 7.4 Axis D — web testing
| Option | Pros | Cons |
|---|---|---|
| **D1. Real Phoenix `Endpoint` (`server:false`) + `Phoenix.ConnTest` via host-kit ConnCase** *(recommended for `phoenix_conncase`)* | exercises the full endpoint plug stack; `json_response/2` sugar; `~p` works; proven (capstone) | needs the prefix-parameterized kit; must start the Endpoint (ETS/persistent_term) |
| **D2. Raw `Plug.Test` + `Router.call(conn, Router.init(opts))`** *(recommended for `plug_selfcontained`; already how 020–025 test)* | zero kit; no Endpoint/ConnCase; no prefix problem | bypasses endpoint-level plugs; no `json_response`/`~p`; harness asserts on `conn.status`/`resp_body` |

`Phoenix.ConnTest.dispatch/5` calls `endpoint.call/2` directly — **no webserver needed**
(`deps/phoenix/…/conn_test.ex:234-238`); the Endpoint must be *started* once (it populates a
config ETS table + `persistent_term`) but `server: false` starts no Cowboy
(`deps/phoenix/…/endpoint/supervisor.ex:101-108, 219-223`).

### 7.5 Axis E — the module-prefix problem (Tier-B only)
| Option | Pros | Cons |
|---|---|---|
| **E1. Fixed namespace** — all Phoenix multifile tasks normalized to `App`/`AppWeb`/`App.Repo` | one *static* kit; zero per-task metadata; simplest to maintain | must rewrite existing bundles (016/017/018 differ); generator constrained to the fixed prefix |
| **E2. Manifest + string-substitution** — manifest declares `prefix`/`otp_app`; kit template substitutes `{{PREFIX}}` *(recommended: keeps existing bundles, proven in capstones)* | preserves bundle variety; single templated kit; mechanical | fragile string edits; must also inject the web-entry module; manifest can drift from code |
| E3. Bundle ships its own Endpoint+ConnCase (like 018) | fully self-consistent; highest fidelity | bloats every bundle; solution author writes test scaffolding (weaker isolation) |
| E4. Router-only dispatch (D2) — drop Endpoint/ConnCase entirely | no prefix problem at all | loses endpoint middleware + `~p` + `json_response` |

---

## 8. Recommended architecture — two-tier evaluator

**A1 (bundle format) · B1 (in-BEAM compile) · C1/C2 (SQLite) · D1+D2 (both web paths) ·
E2 (manifest + substitution).**

Each task dir gains a tiny **`manifest.exs`** (or a header block in `prompt.md`):

```elixir
%{
  multifile: true,
  archetype: :phoenix_conncase,        # :pure_otp | :plug_selfcontained | :ecto_only | :phoenix_conncase
  prefix: "PaginatedList",             # Tier-B only
  web_prefix: "PaginatedListWeb",      # Tier-B only (default: prefix <> "Web")
  otp_app: :paginated_list,            # Tier-B / ecto_only
  db: :sqlite_file,                    # :none | :sqlite_memory | :sqlite_file | :postgres | :fake
  migrations: {:dir, "priv/repo/migrations"},  # or a [{version, Module}] list, or :none
  async: false
}
```

The evaluator:
1. Reads the manifest; parses the `<file>` bundle; materializes it to a temp tree.
2. **Tier A** (`pure_otp`, `plug_selfcontained`, `ecto_only`+FakeRepo): `ParallelCompiler`
   the bundle sources, start ExUnit, compile+run the harness. Done.
3. **Tier B** (`phoenix_conncase`, `ecto_only` with a real Repo): render the **host kit**
   templates with `prefix`/`otp_app`; `put_env` the Repo (SQLite file, Sandbox) + Endpoint
   (`secret_key_base`, `server:false`, `render_errors`); `ParallelCompiler` bundle+kit; start
   `{Repo, Endpoint}` under a supervisor; run bundle migrations in **automatic** mode; switch
   Sandbox to `:manual`; compile+run the harness.
4. Score exactly as today (multi-file analysis per §10).

This is precisely the flow the capstone (§Appendix A.4) executes and passes 14/14 on the real
016 task. Tier A is the flow that passes 18/18 on 102.

The **host kit** ships as templated files under `test/support/kits/phoenix/` (rendered per
task), so it loads through the *existing* `compile_support/1` seam. A canonical, verified kit
skeleton is in Appendix B.

---

## 9. Implementation plan (phased)

Ordered so each phase is independently shippable and unlocks real tasks.

**Phase 0 — bundle unpacker + format validator.** `EvalTask.Bundle.parse/1` +
`materialize/2`; a `validate/1` that rejects fragments (no `defmodule`), duplicate paths,
paths escaping the temp root, and files not under `lib/`/`priv/`/`config/`/`test/`. Wire
`compile_bundle/1` into `eval_task.exs`. **Unlocks nothing yet but is the spine.**

**Phase 1 — Tier A runner.** Detect `multifile` + Tier-A archetype; compile bundle with
`ParallelCompiler`; run harness. **Unlocks 023, 102 immediately** and any future
`pure_otp`/`plug_selfcontained` task. (102 already passes — Appendix A.5.)

**Phase 2 — solve + wire the self-contained Plug tasks.** 020, 021, 022, 024, 025 are
authored but unsolved; with Phase 1 they become gradable. Solve them (they need only
`Plug.Test`). **Unlocks 5 tasks.**

**Phase 3 — Tier B host kit (SQLite).** Add the templated Phoenix+Ecto kit + migration runner
+ boot ordering; render per manifest prefix. **Unlocks 016 and 018** (016 proven; 018 is a
near-complete app needing only ConnCase+Sandbox+boot). Normalize 016/018 harnesses' DB to
file-backed SQLite (or keep Postgres via Phase 5).

**Phase 4 — scoring for multi-file.** Aggregate `analyze_source` across files (§10);
per-file line-length; solution-wide moduledoc/spec presence. Update `run_all.exs` stats +
`tasks_multifile` discovery.

**Phase 5 (optional) — Postgres path.** For tasks whose correctness needs Postgres-only
semantics or true async ConnCase, add a Postgres kit variant (unique DB per eval, `storage_up`,
migrate in `:auto`, `Sandbox.mode(:manual)`, `start_owner!`). Gate behind a `db: :postgres`
manifest value + a `@tag :database`-style opt-in (matches the README's "Postgres only for
database-tagged tasks").

**Phase 6 — normalize existing bundles + fix 017/019.** Enforce the authoring contract
(§9.6): rewrite 017's router fragment into a full module; supply 019's missing migration;
decide 018's DB (SQLite file vs Postgres). **Unlocks 017, 019.**

**Phase 7 — authoring pipeline.** New meta-prompts (`multifile_single_shot_prompt.md`,
`multifile_variation_prompt.md`) that instruct the model to emit `<file>` blocks conforming to
the contract, and a doc addition to `README.md` describing the multifile contribution flow.

### 9.6 The authoring/normalization contract (must-have)
Every multifile solution/response MUST:
- emit each file as a **complete, compilable module** at a **canonical relative path**
  (`lib/<app>/…`, `lib/<app>_web/…`, `priv/repo/migrations/<version>_<name>.exs`,
  `config/*` only if truly needed);
- never emit prose/fragments ("add this to your router") — the 017 failure mode;
- for `phoenix_conncase`, use the **manifest prefix** consistently and rely on the host kit for
  `Endpoint`/`ConnCase`/`Repo`/web-entry (don't hand-roll test support);
- ship a **complete migration** for every table the harness touches (019's gap);
- keep the harness referencing only (a) the solution's public modules and (b) the kit's
  documented support modules.
A CI check (`validate_harnesses.sh` sibling) should compile each bundle+kit and fail on
fragments/missing modules.

---

## 10. Scoring changes (multi-file)

The rubric weights stay (`tests·0.7 + analysis·0.2 + compilation·0.1`). Only `analyze_source`
becomes multi-file:
- **line length / lines>98**: computed per file, reported as the max/aggregate; a single long
  line anywhere counts.
- **`@moduledoc`/`@spec`/`@doc`**: "present" if present in *any* solution module (or, stricter,
  require moduledoc on every `lib/` module — a config knob). Migrations/config excluded.
- **`todo_count` / `sql_injection_risk`**: union across files.
- **`public_fn_count`/`defp_count`/`pipe_chain_count`**: summed.
- **compilation warnings**: already aggregated by `ParallelCompiler`'s diagnostics.
Implementation: pass `analyze_source/1` the list of `{path, source}` for `lib/**/*.ex` and fold.
The host-kit and migration files are **excluded** from analysis (they're infra, not the graded
solution).

---

## 11. Risks & open questions

**Risks / mitigations**
- *Global module namespace collisions* (017/019 both `MyApp`) → keep one OS process per task
  (already true); never batch multifile tasks in one BEAM.
- *SQLite fidelity gaps* (no real FK/constraint names, limited ALTER, five storage classes) →
  offer the Postgres path (Phase 5) for tasks that need it; default SQLite for the rest.
- *`:memory:` dies on process crash* → use temp-file SQLite for Tier-B; `:memory:` fine for
  simple Tier-A/ecto_only.
- *Long-lived eval process atom/ETS growth from compiling many bundles* → per-task OS process
  bounds it (each `System.cmd` is a fresh BEAM that exits).
- *Kit drift vs. Phoenix version bumps* → pin the kit to the repo's Phoenix; a smoke test that
  runs 016+102 in CI catches regressions.
- *Migration-in-a-Task under Sandbox* (`Ecto.Migrator` runs the body in a spawned Task) → run
  migrations before `Sandbox.mode(:manual)` (encoded in the kit).

**Open questions (need a decision)**
1. **Manifest location/format**: a separate `manifest.exs` vs a fenced header in `prompt.md`
   vs inferring archetype from harness heuristics? (Recommend explicit `manifest.exs`.)
2. **Default DB**: SQLite-file everywhere (self-contained, `async:false`), or Postgres for the
   4 Phoenix tasks to preserve their authored `async: true` + real fidelity?
3. **Fixed namespace (E1) vs per-task prefix (E2)**: normalize all future Phoenix tasks to
   `App`/`AppWeb` (simplest kit) or keep per-task prefixes via substitution (keeps existing
   bundles)? (Recommend E2 now, consider E1 for *new* tasks.)
4. **Should the host kit live in-repo** (`test/support/kits/…`, versioned) **or be generated at
   eval time** from templates in the evaluator? (Recommend in-repo templates rendered to temp.)
5. **`018` DB**: keep its authored Postgres target or re-back on SQLite for zero-dependency CI?

---

## 12. Prior art (external) — how other harnesses do this

The design above is a lightweight, in-process instance of well-established patterns. Three
isolation families exist in the literature: **(A) run the real suite in a container**
(SWE-bench, Aider polyglot, DevBench), **(B) exec in-process with a sandbox** (HumanEval/MBPP,
our current single-file harness), **(C) no execution, string similarity** (RepoBench,
CrossCodeEval). Our proposal stays in family B but scales it to multi-file — the pragmatic
choice for a *curated, trusted* dataset where SWE-bench-grade container isolation is overkill.

**Multi-file execution benchmarks (the template for controller+schema+migration):**
- **SWE-bench / Verified / Lite** — real GitHub issue + repo@commit; tasks span multiple files.
  Packaging = 3-layer Docker images (base → env → instance) with `--cache_level`; one container
  per instance. Scoring = apply the model's *unified diff* with `git apply`, run the repo's own
  suite, "resolved" iff patch applies AND all `FAIL_TO_PASS` flip AND all `PASS_TO_PASS` stay
  green (a built-in regression/anti-cheat set). *Lesson we adopt:* **compile-all-then-test
  gating** and a **regression guard**. (arxiv 2310.06770; swebench.com harness reference.)
- **DevBench** — per-repo, Docker; separates **"Environment Setup" as its own scored gate**
  (does it build) from "do tests pass," and feeds *reference* inputs to each stage so a build
  failure doesn't cascade. Uses **coverage %** as continuous partial credit. *Lesson:* treat
  compile as a distinct gate (we already do — `compilation` score) and consider stage isolation.
  (arxiv 2403.08604.)
- **Aider polyglot** — 225 Exercism exercises × 6 langs, Docker-required, real unit tests,
  `pass_rate_1` vs `pass_rate_2` (retry after feeding failing output back). *Lesson:* the
  self-repair loop mirrors this repo's own README workflow (feed the `eval_task` JSON back to
  the model). (github Aider-AI/aider benchmark README.)
- **ClassEval / BigCodeBench** — class/function level; ClassEval reports **class-level AND
  method-level pass@k** (partial credit); BigCodeBench's "calibrated pass@1" injects missing
  imports so trivial omissions don't zero a solution. *Lesson for scoring (§10):* keep a binary
  "resolved" headline **and** a test-pass ratio for partial credit.

**Elixir-specific prior art (validates the in-process approach):**
- **Exercism Elixir test runner** = the closest analogue to our Tier-B: a **fixed host-app
  skeleton** into which the candidate file is dropped, run via `mix test --seed 0 --formatter
  JSONFormatter` where `JSONFormatter` is a **custom ExUnit formatter** emitting machine-
  readable results — exactly the shape of our `FailureCollector`. (github exercism/elixir-test-runner.)
- **`Mix.install/2` single-file scripts** — Wojtek Mach's `ecto_sql.exs` does precisely our
  Tier-B DB flow in one file: `put_env` config → `defmodule Repo` → inline migration →
  `storage_up` → `start_link` → `Ecto.Migrator.run(Repo, [{0, Mod}], :up, all: true)`. Chris
  McCord's "Single File Elixir Scripts" and **Phoenix Playground** (`PhoenixPlayground.start` +
  `PhoenixPlayground.Test`) show the same for a single-file Phoenix endpoint. *We differ only in
  using the project's already-compiled deps instead of `Mix.install` re-resolving them* — faster
  and hermetic to the pinned `mix.lock`. (github wojtekmach/mix_install_examples; hexdocs
  phoenix_playground.)
- **`igniter`** (Sourceror-based, idempotent AST patching) is the tool of choice if we ever move
  to a *generated real project* (option B2) and need to merge a route fragment into an existing
  router — the very operation task 017's fragment implies. (github ash-project/igniter.)

**Interchange format:** the survey ranks robustness as **XML-ish `<file path>` (path decoupled
from content) > unified diff (best for *edits*, needs the base file) > JSON files-map (escaping
fragility) > fenced blocks with a path header (nested-fence breakage — acute for `.ex` with
`"""` heredocs)**. This directly confirms our A1 decision (§5/§7.1): keep `<file>` blocks for
from-scratch generation; reserve diffs only for edit-an-existing-host-file tasks.

**DB hermeticity:** corroborates the C-axis — SQLite `:memory:` (pool_size 1, no async) is the
simplest hermetic default; Ecto SQL Sandbox on shared Postgres gives real fidelity + parallelism
but can't faithfully test code that manages its own transactions; both are in-transaction
sandboxes, so a task whose *subject* is migrations/multi-txn logic needs a fresh throwaway DB.

**Anti-cheating:** EvalPlus expanded HumanEval tests 80× and dropped pass rates up to ~29% —
harnesses that ship thin tests over-credit hardcoded solutions. *Lesson:* multifile harnesses
should keep generous, hidden ExUnit assertions and a fixed seed (this repo's harnesses already
tend to be larger than the solutions).

*Caveats flagged by the research: SWE-bench "score 0 on failed apply" and whether any SWE-bench
task runs a networked DB in-container are inferred, not doc-confirmed; the GitHub Copilot
`// filepath:` and `` ```lang name=path `` conventions are unverified as official specs.*

---

## Appendix A — runnable prototypes (this session)

All executed against the repo's compiled deps; scripts saved under the session scratchpad
`proto/`. Summarized results in §3. Key scripts: `proto1.exs` (multi-module compile),
`proto2.exs` (Ecto+SQLite+migration), `proto3.exs` (Phoenix Endpoint+ConnTest+ExUnit),
`capstone.exs` (real 016 → 14/14), `selfcontained.exs` (real 102 → 18/18),
`capstone017.exs` (017 fragment failure).

## Appendix B — verified host-kit skeleton (Tier B)

The kit below is the one that drove the real `016` harness to **14/14** (Appendix A.4).
`{{PREFIX}}` / `{{WEB}}` / `{{OTP_APP}}` are substituted per the manifest (E2). The evaluator
renders these to the temp support dir, `put_env`s the config, `ParallelCompiler`s bundle+kit,
starts `{Repo, Endpoint}`, runs bundle migrations in **automatic** mode, then flips to manual
sandbox — in that order.

```elixir
# --- config (set BEFORE start_link) ---
Application.put_env(:{{OTP_APP}}, {{PREFIX}}.Repo,
  database: <temp_file_path>,               # file, not :memory:, so the Sandbox pool shares it
  pool: Ecto.Adapters.SQL.Sandbox, pool_size: 5)
Application.put_env(:{{OTP_APP}}, {{WEB}}.Endpoint,
  secret_key_base: String.duplicate("z", 64),
  server: false,                            # no Cowboy; ConnTest calls endpoint.call/2 directly
  render_errors: [formats: [json: {{WEB}}.ErrorJSON], layout: false])

# --- kit modules ---
defmodule {{PREFIX}}.Repo do
  use Ecto.Repo, otp_app: :{{OTP_APP}}, adapter: Ecto.Adapters.SQLite3
end

defmodule {{WEB}} do   # the web-entry the bundle's `use {{WEB}}, :controller/:router` needs
  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]
      import Plug.Conn
      unquote({{WEB}}.verified_routes())
    end
  end
  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
    end
  end
  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes, endpoint: {{WEB}}.Endpoint, router: {{WEB}}.Router
    end
  end
  defmacro __using__(which), do: apply(__MODULE__, which, [])
end

defmodule {{WEB}}.ErrorJSON do
  def render(t, _), do: %{errors: %{detail: Phoenix.Controller.status_message_from_template(t)}}
end

defmodule {{WEB}}.Endpoint do
  use Phoenix.Endpoint, otp_app: :{{OTP_APP}}
  plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json], pass: ["*/*"], json_decoder: Jason
  plug {{WEB}}.Router                          # the bundle supplies {{WEB}}.Router
end

defmodule {{WEB}}.ConnCase do
  use ExUnit.CaseTemplate
  using do
    quote do
      use {{WEB}}, :verified_routes             # enables ~p in the harness (017/018)
      import Plug.Conn
      import Phoenix.ConnTest
      @endpoint {{WEB}}.Endpoint
    end
  end
  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!({{PREFIX}}.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end

# --- boot (in the evaluator, after compiling bundle+kit) ---
{:ok, _} = Supervisor.start_link([{{PREFIX}}.Repo, {{WEB}}.Endpoint], strategy: :one_for_one)
# run bundle migrations in AUTOMATIC mode (they commit to the shared file db):
bundle_migrations |> Enum.with_index(1) |> Enum.each(fn {mod, v} ->
  Ecto.Migrator.up({{PREFIX}}.Repo, v, mod, log: false)
end)
Ecto.Adapters.SQL.Sandbox.mode({{PREFIX}}.Repo, :manual)   # NOW switch to per-test rollback
# then: ExUnit.start(autorun: false); Code.compile_file(harness); ExUnit.run()
```

For `plug_selfcontained`/`pure_otp` (Tier A) there is **no kit** — just
`Kernel.ParallelCompiler.compile(bundle_source_paths)` then run the harness (proven on task 102,
18/18).

## Appendix C — key source citations

- Evaluator seams: `scripts/eval_task.exs:4-7` (dep path), `:112-114,261-264` (single-file
  compile), `:235-248` (`compile_support/1` — kit injection point), `:308-341` (programmatic
  ExUnit), `:359-377` (`analyze_source`); `scripts/run_all.exs:114,118,166-172,174`.
- Phoenix headless: `deps/phoenix/lib/phoenix/test/conn_test.ex:234-238` (dispatch → `call/2`,
  no server), `.../endpoint/supervisor.ex:101-108,219-223` (`server:false` default, no Cowboy),
  `.../verified_routes.ex:246-250` (`~p` needs only `:router`).
- Ecto headless: `deps/ecto_sql/lib/ecto/migrator.ex:245-278` (`up/4`), `:384-459` (`run/4`
  accepts `[{version, module}]`), `:554-566` (schema_migrations auto-created), `:399-410`
  (Sandbox/lock caveat → migrate before manual); `deps/ecto_sqlite3/lib/ecto/adapters/sqlite3.ex:130-135`
  (no async under Sandbox), `:305-308` (`:memory:` ⇒ pool_size 1), `:316-322`
  (`lock_for_migrations` no-op ⇒ migrations fine at pool_size 1).
- Proven patterns in-repo: `tasks/032_00{1..4}/test_harness.exs` (`:memory:`+`delete_all`),
  `tasks_multifile/{016,018}` (real migration + Postgres + ConnCase), `.../102` (FakeRepo).
