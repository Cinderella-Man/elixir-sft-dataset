# 06 — Dataset Multiplication: `wtest` + `tfim` task kinds

> Plan to multiply the corpus by deriving TWO new SFT framings from every solved
> `_01` (which uniquely owns a verified `test_harness.exs`):
>
> 1. **`wtest` — "write tests for this module"**: prompt = the module (+spec) → completion = a test harness.
> 2. **`tfim` — "fill in the middle of the tests"**: prompt = the harness with one block blanked → completion = that block.
>
> Both are minted **fully deterministically** from existing `_01`s (**no LLM**: the reference harness
> is the wtest gold; the `test` name is the tfim spec), graded by the existing evaluator via
> stage-and-delegate (so multifile works for free), and gated by mutation (`wtest`: `gate_base`
> coverage; `tfim`: **isolation-kill**). **Every claim prototyped against the live evaluator — see §10.**

Status: **IMPLEMENTED** 2026-07-02 (grilled + re-prototyped first). See §12 for the as-built delta.

## 0. Decisions locked (grilling pass, 2026-07-02)

Every item below was chosen by the user and/or proven against the live evaluator (§10):

1. **Naming** = prefix `wt_` / `tfim_` (empirically glob-safe; the suffix scheme collides with `count_fim`).
2. **wtest gold** = the parent's existing `test_harness.exs`, verbatim (pure repackage — free, coverage inherited).
3. **wtest prompt** = module source **+ the parent `prompt.md` spec** (clean inverse of `solve`).
4. **tfim targets** = top-level `test` blocks only (median 15/harness; test **name stays visible = the spec**, so tfim is fully deterministic — no LLM).
5. **tfim prompt** = the reference **module source** (fenced) + the whole harness with one `test` body → `# TODO`.
6. **tfim gate** = *isolation-kill* (the blanked block, run **alone**, is green vs the ref module AND kills ≥1 raise-mutant). The plan's original *responsibility-vs-suite* gate is **dead — 0/7 viable** (§10); isolation-kill is **7/7**.
7. **Scope** = single-file **and** multifile `_01`s (10/11 multifile grade green today; skip the 1 Postgres-tier). Variation `_01`s included.

Consequential design facts proven in §10 (not user choices):
- **Runners = stage-and-delegate**: `run_write_test`/`run_test_fim` stage `{module|bundle → solution.ex, harness → test_harness.exs}` in a temp dir and call the existing `run_single`/`run_multifile` — multifile (Tier-A/B, Postgres-skip) handled for free.
- **`EvalTask.Fim.extract_skeleton` must pick the fence containing `# TODO`**, not the first fence (the tfim prompt now has two ```elixir fences: module + harness). This rule also works for sfim's single fence.
- **`EvalTask.Fim.splice` must learn ExUnit openers** (`test|describe|setup|setup_all|property`) beside `def|defp|…`.
- **All coverage/isolation gates shell out per grade** — repeated in-BEAM `ExUnit.run` leaks state (→ `0/0`).

---

## 1. Goal & payoff

Today one `_01` yields: `solve` (prompt→module) + N `sfim` (module-with-hole→function).
This adds, from the SAME `_01`, two more framings the corpus never trained on: **generating
tests** and **completing tests**. Current corpus (measured 2026-07-02):

| | count |
|---|---|
| `_01` dirs (all have a harness) | **178** (167 single-file, 11 multifile) |
| `sfim` subtasks (`_02+`) | 180 |
| `test`/`defp`/`describe` blocks across `_01` harnesses | 2713 / 222 / 51 → ample `tfim` material |

Projected additions: **+~177 `wtest`** (one per gradable `_01` — 167 single-file + 10 multifile; skip
the 1 Postgres-tier) and **+~400 `tfim`** (≤ `GEN_TFIM_MAX_PER_TASK`=3 per `_01`, all viable under the
isolation-kill gate — §10 shows 7/7). ≈ doubles directory count and adds two orthogonal task types.

---

## 2. Task-kind taxonomy + naming extension

Four kinds. Existing two unchanged; two new, distinguished by an **obvious directory prefix**
(mirrors the `fim_` staging-dir idiom, sorts to the end of `ls`, and is glob-safe — §2.1):

| kind | dir pattern | prompt → | gold completion | grading shape |
|---|---|---|---|---|
| `solve` | `a_b_slug_01` | spec | `solution.ex` | `:single` (harness vs candidate) |
| `sfim` | `a_b_slug_0d` (d≥2) | module, 1 fn `# TODO` | that fn | `:fim` (reconstruct module, run parent harness) |
| **`wtest`** | **`wt_a_b_slug`** | module (+spec) | `test_harness.exs` | **`:write_test`** (candidate harness vs ref module) |
| **`tfim`** | **`tfim_a_b_slug_0d`** (d≥2) | harness, 1 block `# TODO` | that block | **`:test_fim`** (reconstruct harness, run vs ref module) |

- One `wtest` per `_01` (single canonical reference harness ⇒ one gold answer).
- `tfim` numbered `_02+` like `sfim`, top-up to `GEN_TFIM_MAX_PER_TASK`.
- `a_b_slug` inside the prefix = the parent `_01`'s stem, so the parent is trivially recoverable.

### 2.1 Glob-safety (why prefixes don't break existing enumeration)

Every existing enumerator is **digit-anchored** or **suffix-anchored** and provably ignores the
lettered prefixes:

| enumerator | glob / test | matches `wt_`/`tfim_`? |
|---|---|---|
| `Catalog.done?` | `tasks/NNN_001_*_01` | no (starts with digits) |
| `Catalog.backfill_seeds` | `tasks/*_01` | no (`wt_…` ends in slug; `tfim_…` ends `_0d`) |
| `Catalog.count_variations` | `tasks/A_00b_*_01` | no |
| `Catalog.count_fim` / `Fim.existing_fim_dirs` | `tasks/A_B_*` (A,B digits) | no |
| `Fim.parent_dir` (`sfim`) | drops last seg + `_01` | n/a (new kinds get own resolver) |
| `Discovery.all` | `tasks/*` then classify by content | **yes — must be taught the prefixes (§4)** |

Only content-classifiers (`Discovery`, `CLI.detect`) and the stats/validate scripts need editing —
exactly the places that *should* change. No rename of the 358 existing dirs.

---

## 3. Directory layouts

### `wt_a_b_slug/`  (wtest) — as-built (§12): the module file is `solution.ex`
```
prompt.md          # "write a comprehensive ExUnit harness" — embeds solution.ex + the parent prompt.md spec
solution.ex        # module under test = copy of parent solution.ex (single-file) OR the <file> bundle (multifile)
test_harness.exs   # GOLD completion  = copy of parent test_harness.exs (the SFT target & default gradable)
```
Using `solution.ex` makes the dir structurally a normal task, so it grades through the existing
`run_single`/`run_multifile`. For a multifile parent, `solution.ex` holds the `<file>` bundle verbatim.

### `tfim_a_b_slug_0d/`  (tfim)
```
prompt.md    # the reference module in one ```elixir fence, THEN the whole harness in a second ```elixir
             # fence with one `test "…"` BODY → `# TODO` (the test name line is kept = the spec)
solution.ex  # GOLD completion = just that one `test "…" do … end` block
```
No harness of its own (like `sfim`); the reference module lives in the parent `a_b_slug_01/solution.ex`
(or its `<file>` bundle). Targets are top-level `test` blocks only (decision §0.4).

---

## 4. Grading (evaluator additions)

Two new shapes, dispatched by **prefix** so they resolve *before* the harness-less `:fim` default.

`EvalTask.CLI.detect/2` (`lib/eval_task/cli.ex:62`) and `Discovery.annotate/2`
(`lib/eval_task/discovery.ex:30`) gain, first:
```elixir
String.starts_with?(base, "wt_")   -> :write_test
String.starts_with?(base, "tfim_") -> :test_fim
```
Discovery sets the default gradable file per shape: `wtest → test_harness.exs`, `tfim → solution.ex`.

New runners in `lib/eval_task/runner.ex` — both **stage-and-delegate** (proven §10), so multifile
bundles reuse `run_multifile` (Tier-A/B + Postgres-skip) unchanged:

- **`run_write_test(dir, candidate)`** — stage a temp dir `{solution.ex ← dir/module.ex,
  test_harness.exs ← candidate}` (candidate defaults to `dir/test_harness.exs`), then dispatch by
  `Bundle.bundle?(module)` → `run_single`/`run_multifile`. Green ⇔ the candidate harness passes the
  reference module. Analysis in `:fim` mode (no doc points — it's a test file). *Coverage is an
  authoring gate, not a per-run score (§4.1).*
- **`run_test_fim(dir, candidate)`** — resolve parent via new `Fim.test_fim_parent_dir/1` (strip
  `tfim_` prefix, drop last seg, `+ _01`); read the parent module (`solution.ex`/bundle); extract the
  **harness** skeleton from `dir/prompt.md` (the ```elixir fence containing `# TODO` — see below);
  **splice** candidate at the marker; stage `{solution.ex ← parent module, test_harness.exs ←
  reconstructed}` and delegate as above. Green ⇔ the completed harness passes the reference module.

**Two proven `EvalTask.Fim` fixes (§10):**
1. **`extract_skeleton` must pick the fence containing `# TODO`**, not the first fence — the tfim
   `prompt.md` now has two ```elixir fences (module, then harness). This unified rule also works for
   sfim (its single fence contains the TODO). Verified: it selects the harness, not the module.
2. **`splice/2` + `scan_up_for_def/2` must learn ExUnit openers** — extend the regex to
   `~r/^\s*(def|defp|defmacro|defmacrop|test|describe|setup|setup_all|property)\b/`. A blanked
   `test "…"` block then reconstructs **byte-identical** (verified 7/7).

### 4.1 Non-vacuity gates (authoring + `validate.exs`, NOT inside one eval)

Green-but-vacuous completions must be rejected. This needs N mutant runs in **separate OS processes**
(a single-BEAM eval leaks ExUnit state across runs → `0/0` — proven §10), so it lives where grading
already shells out (`GenTask.Mutation`, `validate.exs`), like `sfim`.

- **`wtest` coverage** — reuse `GenTask.Mutation.gate_base` (stage `%{"solution.ex" => module,
  "test_harness.exs" => candidate}`): for each public fn, raise-mutant → the candidate harness must
  FAIL. Proven: the gold harness kills every public-fn mutant; a `assert true` harness kills none ⇒
  rejected. For the **gold** wtest this is *inherited* (the parent `_01` already passed the base
  per-fn gate), so minting needs no re-check; the gate matters only when scoring an arbitrary
  candidate harness. Multifile: coverage inherited from the parent's `validate.exs` reference-green.
- **`tfim` isolation-kill** — ⚠ the plan's original *responsibility-vs-suite* gate is **DEAD**: on
  107_001, **0/7** test blocks had any responsibility, because the suite is redundant (every test
  drives every function, so removing any one test still leaves others to kill each raise-mutant).
  **Replacement (proven 7/7):** a `test` block is a valid tfim target iff, run **in isolation** (that
  test + the harness's helpers/`setup`, all other `test` blocks removed), it (a) is green vs the ref
  module and (b) kills ≥1 per-fn raise-mutant (`def` **and** `defp`). Cheap: isolate once, run vs
  mutants with early-exit on first kill. Multifile: bundle-level mutation is deferred → use the
  reduced gate (reconstruct-green + isolation-green + ≥1 static assertion in the block).

---

## 5. Generation loop (new modules + chaining)

Both minted **fully deterministically** from an accepted `_01` — **no LLM at all** (the `test` name is
the tfim spec; the reference harness is the wtest gold). Backfilling all gradable `_01`s is minutes.

- **`GenTask.WriteTest.run(seed, cfg)`** → mints `wt_a_b_slug/`: `module.ex` = seed `solution.ex` (or
  bundle); `test_harness.exs` = seed `test_harness.exs`; `prompt.md` = template embedding the module +
  the seed `prompt.md` spec. Skip if the seed is Postgres-tier (grades `skipped`). Coverage inherited;
  promote via `Cycle.promote`. Essentially free — one gold suite per `_01`.
- **`GenTask.TestFim.run(seed, cfg)`** → carves ≤`tfim_max` `tfim_a_b_slug_0d/`: indent-scan
  `test_harness.exs` for top-level `test "…"` blocks (indent-aware so `describe`-nested tests are
  reachable — 8 harnesses are fully nested; skip those in v1 if not handled). For each candidate
  block apply the **isolation-kill gate** (§4.1); keep the survivors ranked (e.g. by #mutants killed
  or assert count) up to `tfim_max`. Write `prompt.md` (module fence + harness with that block body →
  `# TODO`) + `solution.ex` (the block). Accept = reconstruct-green (true by construction) + gate passed.

Chaining in `GenTask.CLI`:
- `run_base_item` (`cli.ex:98`), after `run_fim`: `run_write_test(cfg, [seed | variation_seeds])`
  then `run_test_fim(...)`.
- `run_backfill_item` (`cli.ex:126`): add the two, gated by new `seed.needs_write_test?` /
  `seed.needs_test_fim?`.
- `run_write_test`/`run_test_fim` respect `cfg.skip_write_test` / `cfg.skip_test_fim`.

---

## 6. Backfill (catalog)

`Catalog.Seed` (`catalog.ex:40`) gains `needs_write_test?` + `needs_test_fim?`. `seed/2`
(`catalog.ex:198`):
```elixir
needs_write_test?: not gradable_skip? and not File.dir?("#{tasks_dir}/wt_#{a}_#{b}_#{slug}")  # 0 or 1
needs_test_fim?:   not gradable_skip? and count_tfim(cfg.tasks_dir, a, b) < cfg.tfim_max_per_task  # top-up
```
`backfill_seeds` filter (`catalog.ex:194`) also admits `needs_write_test? or needs_test_fim?`. New
`count_tfim/3` globs `tasks/tfim_A_B_*`. `gradable_skip?` excludes Postgres-tier seeds (their eval is
`skipped` — e.g. `017_001`). Because both derivatives are cheap+deterministic (no LLM), a full backfill
over the ~177 gradable `_01`s is minutes, not hours.

---

## 7. Config flags (`GenTask.Config`, docs/04 §15)

| field | env | default | gates |
|---|---|---|---|
| `skip_write_test` | `GEN_SKIP_WRITE_TEST` | off | skip wtest generation |
| `skip_test_fim` | `GEN_SKIP_TEST_FIM` | off | skip tfim generation |
| `tfim_max_per_task` | `GEN_TFIM_MAX_PER_TASK` | 3 | tfim top-up cap per `_01` |

(Optionally extend `GEN_ONLY` to accept `wtest`/`tfim`.)

---

## 8. Concrete change checklist (file → edit)

**Evaluator**
- `lib/eval_task/cli.ex:62` `detect/2` — prefix branches → `:write_test` / `:test_fim` (before `:fim`); `main/1:42` dispatch.
- `lib/eval_task/discovery.ex:30` `annotate/2` — prefix branches + per-shape default gradable file (`wt_ → test_harness.exs`, `tfim_ → solution.ex`).
- `lib/eval_task/runner.ex` — `run_write_test/2`, `run_test_fim/2` as **stage-and-delegate** wrappers over `run_single`/`run_multifile`.
- `lib/eval_task/fim.ex` — (1) `extract_skeleton` → pick the fence containing `# TODO`; (2) extend `splice`/`scan_up_for_def` openers; (3) add `test_fim_parent_dir/1`.
- `lib/eval_task/analysis.ex` — `:fim` mode for both (no doc points on a test file).

**Generation loop**
- `lib/gen_task/write_test.ex` (new — repackage), `lib/gen_task/test_fim.ex` (new — carve + isolation-kill).
- `lib/gen_task/config.ex:49/84` — 3 new fields + env parse.
- `lib/gen_task/catalog.ex:40/198/194` — `Seed` fields (+`gradable_skip?`), `seed/2`, `backfill_seeds` filter, `count_tfim/3`.
- `lib/gen_task/cli.ex:98/126` — chain in base + backfill; `run_write_test`/`run_test_fim` drivers.
- `lib/gen_task/mutation.ex` — add `gate_isolation/…` (isolate a test block, mutate `def`+`defp`, require ≥1 kill); reuse `gate_base` for wtest. NB: extend the per-fn mutator to `defp`, not only `def`.
- `lib/gen_task/prompts.ex` — `write_test/2` template (module + spec). **No tfim prompt builder needed** (deterministic carve keeps the `test` name as the spec).

**Scripts**
- `scripts/dataset_stats.exs:46/144/160` — prefix-aware `parse_name`/row flags; `wtest`/`tfim` corpus buckets + pair framings ("module→tests", "test-FIM prompt→block"). Do **not** fold wt/tfim into solution-quality stats (their "solution" is a harness/test block).
- `scripts/validate.exs:42/64` — `wtest` coverage check (gate_base) + `tfim` isolation-kill check (both via `Discovery` shape, shelling out).
- `scripts/run_all.exs` — works once Discovery classifies (passes `task.solution` per shape); verified by the delegation prototype.

**Docs**
- `CONTEXT.md`: §3 naming (107), §4 file types (143), §5 evaluator (171), §6 authoring (236), At-a-glance (38); refresh the 2026-07-01 banner (8).
- `README.md`: Naming convention (64), How to contribute (86) — 2 new activities, config note (229).
- `docs/04`: new §s for WriteTest/TestFim generators, work-list (§4), catalog (§5), §15 flags, §16 module layout.
- `docs/05`: note new paths. Meta-prompts (optional): `tasks/write_tests_prompt.md`, `tasks/test_fim_prompt.md`.

---

## 9. Rollout order

1. `Fim.extract_skeleton`+`splice` fixes + `test_fim_parent_dir/1` + `detect`/`Discovery` prefixes + two stage-and-delegate runners (+ unit tests).
2. `run_all`/`validate`/`dataset_stats` prefix-awareness.
3. Hand-mint ONE `wt_` + ONE `tfim_` from `107_001` (proven format), grade via `eval_task.exs`, commit as fixtures.
4. `GenTask.WriteTest` (repackage) + `GenTask.TestFim` (carve + isolation-kill) + config + catalog backfill + chaining; extend the per-fn mutator to `defp`.
5. `GEN_ONLY=backfill GEN_SKIP_VARIATIONS=1 GEN_SKIP_FIM=1` dry-run → then live over the ~177 gradable `_01`s (single-file + 10 multifile; skip Postgres-tier).
6. Docs.

---

## 10. Prototype evidence (live evaluator; `107_001_event_aggregator` + the 11 multifile `_01`s)

Every grade in an **isolated OS process** (`scripts/eval_task.exs`), as `GenTask.Evaluator.grade` does.

**wtest**
- [A1] gold harness vs gold module → green **7/7**.
- [A2] coverage: a raise-mutant of every public fn (`start_link/1`,`push/2`,`init/1`,`handle_cast/2`,
  `handle_info/2`) makes the harness **FAIL (killed)** — `gate_base` reused verbatim.
- [A3] a vacuous `assert true` candidate → green-vs-module **true** but kills-mutant **false** ⇒
  correctly **REJECTED**.

**tfim**
- [B1] blank a `defp` helper → reconstruct → green **7/7**.
- [B2] blank a `test "…"` block → **extended splice** reconstructs **byte-identical** → green **7/7**
  (stock splice fails — hence the opener fix).
- [B-e2e] tfim prompt with **two** ```elixir fences (module + harness): "fence containing `# TODO`"
  extractor picks the harness (not the module); gold completion → green **7/7**; a wrong completion
  (flip `refute`→`assert`) → **6/7 (caught)**.
- [B-gate ✗→✓] the **responsibility-vs-suite** gate is **0/7 viable** (suite redundancy — every test
  drives every fn, so removing one never frees a mutant, even over `def`+`defp` mutants). The
  **isolation-kill** gate is **7/7** viable: each test alone stays green and kills 2–10 mutants (even
  the lone `refute_receive` test kills 2). ⇒ §4.1 rewritten.

**Infrastructure**
- **Stage-and-delegate** proven: staging `{bundle→solution.ex, harness→test_harness.exs}` and grading
  reproduces multifile **31/31** ⇒ wtest/tfim reuse `run_multifile` for free.
- **Multifile gradability**: 10/11 multifile `_01`s grade green today (14–31 tests); only `017_001` is
  Postgres-skipped.
- **Glob-safety** empirically confirmed: with `wt_`/`tfim_` dirs present, `count_variations`=0,
  `count_fim`=1, `backfill_seeds`={only the real `_01`}; `detect` misclassifies both today (→ needs the
  prefix branches). Suffix scheme rejected (its `tfim_…_0d` collides with `count_fim`).
- **In-BEAM `ExUnit.run` leaks state** across repeated runs (→ `0/0`) ⇒ all gates shell out per grade.

---

## 11. Resolved (grilling) + still-open

**Resolved** — see §0: naming (prefix), wtest gold (reuse), wtest prompt (module+spec), tfim targets
(`test` blocks), tfim prompt (module+harness), tfim gate (isolation-kill), scope (single-file +
multifile). Determinism: **no LLM** for either kind. Runners: stage-and-delegate.

**Still open (minor / tuning):**
1. **`describe`-nested tests** (8 harnesses, all-nested): handle via indent-aware carving, or skip in
   v1? (Recommend skip in v1; revisit.)
2. **Multifile tfim gate**: bundle-level mutation is deferred → reduced gate (reconstruct-green +
   isolation-green + ≥1 static assertion). Accept the weaker guarantee for the 10 multifile tasks, or
   invest in bundle mutation? (Recommend accept for v1.)
3. **`tfim_max_per_task`** default 3 — raise for more data (median 15 blocks available)? Tuning knob.
4. **Per-candidate eval score** for wtest/tfim reflects only green + analysis, not coverage (coverage
   is an authoring/validate gate — a lazy candidate could still score high when *benchmarking* models).
   Fine for data-gen; note as a known limitation if a wtest/tfim *benchmark* is built later.
5. **`GEN_ONLY`** extend to accept `wtest`/`tfim` scopes? (Nice-to-have.)

---

## 12. As-built delta (implementation, 2026-07-02)

One deliberate simplification vs the plan, plus the concrete module map:

- **wtest module file is `solution.ex`, not `module.ex`.** A `wt_<a>_<b>_<slug>/` dir therefore holds
  `{prompt.md, solution.ex (the module), test_harness.exs (the gold completion)}` — structurally a
  normal task, so it grades through the existing `run_single`/`run_multifile` unchanged (the `:write_test`
  runner just dispatches by `Bundle.bundle?`). The prefix drives shape-bucketing; the SFT completion is
  still `test_harness.exs`. This removed a class of tooling special-cases (Discovery/stats/run_all read
  `solution.ex` and "just work"). tfim dir = `{prompt.md, solution.ex (the gold test block)}`, harness-less.
- **Shapes wired in** `EvalTask.CLI.detect/2` + `main/1` dispatch + `Discovery.annotate/2` (prefix
  branches), `Runner.run_write_test/2` + `run_test_fim/2` (stage-and-delegate), `Fim.extract_skeleton`
  (TODO-fence), `Fim.splice`/`scan_up_for_def` (`@block_opener` incl. ExUnit macros), `Fim.test_fim_parent_dir/1`.
- **Generation** `GenTask.WriteTest` (repackage), `GenTask.TestFim` (carve + isolation-kill),
  `Mutation.mutate_fn/4` (`:defp`) + `Mutation.all_functions/1` + `Mutation.gate_isolation/4`
  (green-sanity + ≥1 kill), `Config` (`skip_write_test`/`skip_test_fim`/`tfim_max_per_task` ←
  `GEN_SKIP_WRITE_TEST`/`GEN_SKIP_TEST_FIM`/`GEN_TFIM_MAX_PER_TASK`), `Catalog.Seed`
  (`needs_write_test?`/`needs_test_fim?` + `count_tfim/3`), `CLI` chaining in base + backfill.
- **Backfill** is deterministic (no LLM): `GEN_ONLY=backfill GEN_SKIP_VARIATIONS=1 GEN_SKIP_FIM=1
  mix run scripts/generate.exs`.
- **Operational gotcha**: `scripts/eval_task.exs` prepends `_build/test/lib/*/ebin` **last** (it shadows
  dev), so run `MIX_ENV=test mix compile` (as well as `mix compile`) after editing `lib/` before grading.
