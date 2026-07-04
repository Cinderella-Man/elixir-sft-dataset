# 07 — Dataset Audit & Growth Roadmap

> **Date:** 2026-07-03 · **Verified:** same day — all §6 claims re-checked against
> source (17/18 confirmed, 1 stale claim corrected), §7 numbers re-measured against
> the corpus (exact), the 9 ecosystem claims fact-checked against current hexdocs,
> and the four key §4 mechanisms **prototyped end-to-end against the real
> evaluator (4/4 viable)**. See §11 and `docs/prototypes/proto_*.exs`.
> **Scope:** A full audit of the corpus, the generation/eval pipeline (`lib/gen_task/**`,
> `lib/eval_task/**`, `scripts/`), the idea catalogs (`tasks/tasks.md`,
> `tasks/tasks_external.md`), and the design docs (`docs/01`–`06`,
> `BACKFILL_PROGRESS.md`) — answering four questions:
>
> 1. What could be improved in `scripts/` and `lib/`?
> 2. What is the dataset missing?
> 3. What are the quick wins to multiply the amount of data?
> 4. How do we cover the full space of daily Elixir developer tasks — Phoenix,
>    LiveView, Ash, auth, Jason, all the way to Nx, Bumblebee, and nicher stuff?
>
> Method: `mix run scripts/dataset_stats.exs` on the live corpus, a code audit of every
> module in `lib/gen_task/` and `lib/eval_task/` plus all scripts, a keyword-bucketed
> topic classification of both catalogs cross-referenced against realized task dirs,
> and a review of every open item recorded in docs/03 §12–13, docs/05, docs/06 §11,
> and BACKFILL_PROGRESS.md.

---

## 1. Executive summary

- The corpus stands at **1,395 gradable examples (~4.8M tokens)** across five framings,
  but covers only **83 of 1,000 catalog ideas (8.3%)** — and only **15 of 442
  external-dep ideas (3.4%)**. Realized coverage is concentrated in OTP/GenServer
  territory (ideas ≤ 110 plus 131/134/623–626); ~half of all task dirs are
  GenServer-shaped.
- The single biggest SFT-quality problem is **prompt-register monoculture**: virtually
  every base prompt opens *"Write me an Elixir module called X"* with a fully
  enumerated API; 400/407 harness-bearing tasks carry the same "single file, stdlib
  only" closing constraint; all 631 FIM prompts open "# Fill in", all 203 wtest
  prompts open "# Write tests". Real user traffic is vague, buggy, multi-turn, and
  rarely specifies the API. No doc or meta-prompt addresses stylistic diversity.
- The **highest-leverage untapped multipliers are deterministic (zero LLM cost)**:
  raising the tfim cap (measured: 3–4× tfim yield at cap 10–15; all 193 producing
  parents sit exactly at today's cap of 3), minting repair pairs from the loop's own
  discarded repair traffic, mutant-repair tasks from the mutation gate's existing
  output, de-documentation pairs, and inverse (code→spec) pairs. Together these are
  worth roughly **+3,000–4,000 verified examples** without a single LLM call.
  **The four key mechanisms were prototyped against the real evaluator and all four
  are viable — see §11 and `docs/prototypes/proto_*.exs`.**
- Several **known-blocked yields** have fixes already drafted in the docs but not
  applied: describe-nested tfim carving (24 harnesses currently yield 0 tfim),
  the multifile-FIM prompt fix (Finding D), the `cli.ex` Finding A patch, and the
  missing `tasks.md` base entries 16–25 (Finding E — their variations are being
  silently discarded today).
- The catalog itself has **structural blind spots**: Ash has effectively 0 ideas,
  Bumblebee/Axon/Scholar 0 mentions, umbrella apps 0, real `mix release` workflows
  ~0, auth *libraries* (Joken/Guardian/bcrypt) ~0 (all 37 auth ideas are hand-rolled),
  and much of the external catalog is "Mini X" *reimplementations* rather than
  *use-the-library* tasks — the opposite of daily developer work.
- Five deps in `mix.exs` are installed and **used by zero tasks**: `req`, `nx`,
  `explorer`, `phoenix_live_view`, `mox` (plus `plug_cowboy` and effectively
  `postgrex`). LiveView is the standout: 35 catalog ideas, dep installed,
  `Phoenix.LiveViewTest` runs fully in-BEAM — and 0 tasks built.

---

## 2. Current state of the corpus (measured 2026-07-03)

From `mix run scripts/dataset_stats.exs`:

| Metric | Value |
|---|---|
| Task directories (all gradable) | **1,395** |
| By shape | single 193 · fim 409 · write_test 203 · test_fim 579 · multifile 11 |
| Base tasks / variations / FIM | 83 / 121 / 409 |
| Distinct ideas covered | **83** of 1,000 (8.3%) |
| Dirs with `test_harness.exs` | 407 (204 `_01` base/variation dirs) |
| Total est. tokens (prompt+solution+harness) | **4,766,214** |
| — prompts / solutions / harnesses | 68.7% / 15.2% / 16.0% |
| prompt+solution per example | med 2,632 · mean 2,868 · p90 4,751 · max 8,631 tok |
| Fits in 8k context | 99.9% of examples |
| @moduledoc / @spec / @doc (refs) | 99.0% / 89.7% / 72.5% |
| Alternate-model solutions | **1** (`076_001_trie_01/solution_Qwen3.5-4B-Q6_K_gguf.ex`) |
| OTP constructs in solutions | GenServer 240 · GenStage/Task 38 · ETS 12 · Ecto 9 |

**Realized idea numbers:** 1–25, 31–45, 61–65, 70–80, 86–87, 89, 91–92, 95–110, 131,
134, 623–626. Everything else — the entire 111–622 and 627–1000 span minus the four
623–626 minis — is pure backlog.

**SFT framings currently minted:**

| Framing | Count | LLM cost to mint |
|---|---|---|
| prompt → solution (base/variation/multifile) | 204 + 11 | 2 calls (base) / 1 N-in-one call (variations) |
| code FIM (module-with-`# TODO` → one function) | 409 | 2 calls per subtask (selection + candidate) |
| write-tests (module+spec → harness) | 203 | **0 — deterministic** (docs/06) |
| test-FIM (harness-with-one-test-blanked → test) | 579 | **0 — deterministic** (docs/06) |

---

## 3. Prompt diversity — the biggest quality gap

Measured directly on the corpus:

- First-3-words histogram over all 1,395 `prompt.md` files:
  `# Fill in` ×631, `# Write tests` ×203, `Implement the private` ×192,
  `Write me an` ×125, `Implement the public` ×23, `Implement the handle_call/3` ×21, …
  **There is essentially one register per shape.**
- 378 prompts contain the literal phrase "single file"; 400 contain
  "no external dependencies / only OTP / standard library".
- Root cause: `lib/gen_task/prompts.ex:13-17` inlines the task-001 rate-limiter
  triplet **at compile time as the single few-shot exemplar for every base
  generation**. One fixed exemplar → every generated prompt sounds like the same
  user asking for the same kind of GenServer. The manual meta-prompts
  (`tasks/single_shot_prompt.md` etc.) have the same property — a single exemplar,
  imperative spec-sheet style. `variation_prompt.md`'s "differ just a little bit"
  additionally pulls variations toward near-clones in the same voice.
- **Nothing anywhere addresses:** vague/underspecified requests, bug-report-style
  prompts ("this crashes when…" → fix), code-review framings, multi-turn follow-ups,
  prompts that omit the API and let the model design it, persona/register variation,
  or non-native-English phrasing. The only diversity in the corpus is *structural*
  (solve/fim/wtest/tfim/multifile), not *stylistic*.

Why this matters for SFT: a model tuned on 1,395 examples of one register learns the
register, not the skill transfer. The fix is cheap (§5.1) because the harness — the
expensive verified part — is invariant under prompt rewording.

---

## 4. Quick wins — deterministic multipliers (zero LLM cost)

Ranked by yield ÷ effort. All of these follow the existing docs/06 philosophy:
deterministic minting gated by the already-verified harness.

### 4.1 Raise `GEN_TFIM_MAX_PER_TASK` above 3 — ~3–4× tfim yield ✅ VERIFIED

**Measured with the production carver** (`GenTask.TestFim.test_blocks/1`, see
`docs/prototypes/proto_tfim_yield.exs`): the 204 harnesses hold **3,003 carvable
top-level `test` blocks** (median 14, max 41). The model is exact: cap-3 predicts
582 vs the 579 actually on disk — and **all 193 tfim-producing parents sit at
exactly 3**, so yield is provably cap-limited, not gate-limited. Projected yield
(upper bounds, before isolation-kill attrition):

| cap | tfim dirs |
|---|---|
| 3 (today) | 582 (579 actual) |
| 10 | **1,897** |
| 15 | **2,514** |
| uncapped | 3,003 |

Cost: gate compute only (reconstruct-green + isolation-kill per block).
Recommendation: raise to 10, run `GEN_ONLY=backfill GEN_SKIP_VARIATIONS=1
GEN_SKIP_FIM=1`, and add the negative cache first (§6.2) so re-runs don't re-gate
rejects. Additionally, 24 harness files hold **452 tests nested inside `describe`
blocks** (7% of all tests) invisible to the 2-space carver, and `property` blocks
(2 harnesses) are never carved — both extra headroom behind the indent-aware
carving fix (§4.7).

### 4.2 Mint repair pairs from the loop's own exhaust — a new task family, free

**This is the most valuable data currently being thrown away.** Every rejected
attempt inside `GenTask.Cycle.run` (`cycle.ex:43-67`) produces:

1. the broken candidate files (staged in `.gen_staging/`, then `File.rm_rf!`-ed at
   `evaluator.ex:29`),
2. a structured failure report (`Evaluator.repair_report` — compile diagnostics +
   per-test failure messages via `EvalTask.FailureCollector`), and
3. when a later attempt succeeds, the fixed files.

That is a **verified bug → diagnosis → fix triple**, and chained across attempts a
natural **multi-turn conversation** ("write X" → broken answer → "these tests
fail: …" → fixed answer) — a framing the corpus has *zero* of today. Currently these
exist only as `Logger.debug` lines in gitignored `logs/<task_id>.log`, and failed
cycles' logs are even *deleted* when a later attempt succeeds (`cycle_log.ex:72-77`).

✅ **Capture point verified:** in the reject branch of `Cycle.run` (`cycle.ex:53-64`)
the candidate `files`, the `grade` JSON (with `test_failures`), and the reject
`reason` are all in scope — persisting them is a genuinely small change. The
repair-prompt assembly itself is prototyped end-to-end in
`docs/prototypes/proto_mutant_repair.exs` (same mechanics, mutant-sourced).

**Implementation sketch:**
- In `Cycle.run`, after each graded attempt, persist
  `logs/attempts/<task_id>/attempt_<n>/{files/, grade.json, repair_prompt.md}`
  (a few lines around `cycle.ex:60-64`).
- Add `scripts/mint_repairs.exs`: for each task with ≥2 attempts where the last is
  accepted, emit `repair_<a>_<b>_<slug>/` dirs — `prompt.md` = original request +
  broken code + failure report; `solution.ex` = the accepted fix; grading reuses the
  parent harness (shape detectable by a `repair_` prefix, same pattern as `wt_`/`tfim_`).
- Yield: the backfill run alone logged 209 accepted items; historical accept-rates
  suggest **hundreds of pairs**, growing automatically with every future loop run.

### 4.3 Mutant-repair tasks — ~1,000 examples from data the gate already computes

`GenTask.Mutation.mutate_fn/4` deterministically produces a broken module (one
function body → `raise`), and the per-function mutation gate
(`mutation.ex:179-196`) **already runs the harness against it and captures the
failing-test JSON** during acceptance. Package each (mutated module, failure output)
as a *"these tests fail — find and fix the bug"* task whose gold is the original
function. ~204 `_01` dirs × ~5 public functions ≈ **~1,000 examples**, minted from
byproducts of a gate that already runs.

✅ **PROTOTYPED VIABLE** (`docs/prototypes/proto_mutant_repair.exs`): mutating
`call/2` of 002_001 yields 14/15 failing tests with per-test failure messages
captured in the eval JSON; the assembled repair prompt is ~5.7KB; the gold re-grades
15/15 (1.0). **One important caveat found:** the `raise`-mutant's failure messages
are all the uniform string `"MUTATION"` — fine for gating, weak as a repair-prompt
diagnostic. Production should add subtler deterministic operators (off-by-one,
swapped clauses, dropped guard, inverted comparison) so failure output looks like a
real bug report.

### 4.4 De-documentation pairs — ~200+ examples

The quality gate (`evaluator.ex:122-136`) guarantees every accepted reference has
`@moduledoc`/`@spec`/`@doc`. Strip them with a deterministic pass →
*"add typespecs and documentation to this module"* with the original as gold, graded
by the existing analysis rubric plus a diff-must-not-change-behavior check (parent
harness stays green). Teaches exactly the house style the rubric rewards.

✅ **PROTOTYPED VIABLE** (`docs/prototypes/proto_dedoc.exs`): a heredoc-aware
line-scan strip (AST round-tripping would lose comments/formatting) verified on
3 tasks — stripped modules stay green (15/15, 20/20, 26/26) and overall drops
1.0 → 0.85–0.87, i.e. the docs are exactly the score delta the trainee must supply.
Bad strips self-filter because every minted pair is graded before promotion.

### 4.5 Inverse / explain pairs — ~200+ examples

Every `_01` triplet is a gold (spec → code) pair; reversed it is a gold
(code → spec/explanation) pair: *"explain what this module does and document its
public API"* with `prompt.md` as reference. Grading is soft (LLM-judge or
rubric-lite), so mark these `analysis-only` if you want to keep the hard-verified
core pure — still valuable SFT signal for the explain/review register.

### 4.6 Deterministic sfim — replace 2 LLM calls per FIM subtask with ~0–1

Code-FIM currently spends an LLM call on target selection (`fim.ex:136-173`) and one
per candidate on skeleton+gold generation (`fim.ex:213-248`). But tfim proves the
whole mechanism can be deterministic: `Mutation.all_functions/1` already enumerates
targets, the skeleton is a source-level carve (body → `# TODO`), and the gold is the
function's source slice. Only the one-paragraph NL description is generative — and
even that can be templated from the function's `@doc`. Converting sfim to the tfim
technique makes FIM top-up nearly free and unblocks it from usage-limit windows.

✅ **PROTOTYPED VIABLE** (`docs/prototypes/proto_det_sfim.exs`), including the hard
case: carving the **multi-clause** `handle_call/3` from 002_001 with zero LLM calls
produced a FIM dir the real evaluator detects (`shape=fim`), reconstructs, and
passes 15/15 (overall 0.92). Note the carve must be source-level line-scanning, not
AST → `Macro.to_string` (comments and `# TODO` markers don't survive the AST).
**Production fix needed over the prototype:** blank *all* clauses of the target into
a **single** stub — the prototype left one stub per clause and `Fim.splice/2`
replaces only the one containing the first marker, leaving dead stubs behind
(compiles and passes, but emits clause warnings — the 0.92 instead of higher).

### 4.7 Unlock known-blocked yield (fixes already drafted in docs)

| Item | Where documented | Yield |
|---|---|---|
| describe-nested tfim carving (indent-aware) | docs/06 §11.1, BACKFILL Finding C | ✅ measured: 24 harness files hold **452 tests inside `describe` blocks** (7% of all tests) invisible to the 2-space carver; 10 harnesses have *zero* carvable top-level tests |
| Multifile-parent sfim `:contract` rejects — prompt must ask for one function, not a `<file>` bundle | BACKFILL Finding D (:100-103) | ~10 Phoenix `_01`s currently get no sfim |
| Finding A: `cli.ex` `run_backfill_item` still derives wt/tfim for self-seed unconditionally | BACKFILL C7 :137-140 (patch drafted) | stops wasted re-gating (e.g. 017_001 re-attempts 23 tfim + 1 wt every run) |
| Finding E: ideas 16–25 have no `### N.` base lines in tasks.md → `insert_variation!` hits `:base_not_found` and **silently discards** new variations | BACKFILL :142-153 | restores variation cataloging for 10 realized ideas; then `GEN_RECONCILE=1` |
| `property` blocks as tfim targets | not yet proposed | StreamData harnesses (30 uses) currently contribute nothing to tfim |

### 4.8 Negative / preference data via the existing alternate-solution mechanism

`run_all.exs` already scores any `solution_<MODEL>.ex` against the fixed harness, but
only **one** alternate exists (a broken Qwen3.5-4B trie). Run a handful of small local
models across all 407 harness-bearing tasks:

- graded failures → **rejected responses for DPO/preference tuning** (chosen = reference);
- their failure JSONs → more §4.2-style repair prompts;
- pass-rate per task doubles as a *difficulty calibration* signal for curriculum
  ordering.

Zero authoring cost; pure compute.

---

## 5. LLM-assisted multipliers (cheap, high leverage)

### 5.1 Prompt-register rewriting — ×3–5 on existing tasks AND the diversity fix

For each existing task, generate K rewrites of `prompt.md` in distinct registers,
keeping `solution.ex` and `test_harness.exs` byte-identical (verification stays
free — the pair is already gold):

1. **Vague/underspecified** — "I need something to stop users hammering my API" (no
   API given; solution shows *a* correct design).
2. **Bug-report** — embed a subtly broken variant (from §4.3 mutants!) + symptom
   description; completion = the fix.
3. **Code-review** — "review this module; fix anything wrong" over a mutant or a
   style-violating variant.
4. **Terse/Slack-style**, **non-native phrasing**, **requirements-list format**,
   **"design the API yourself"**.

One cheap LLM call per rewrite (temperature up, style-instruction rotated); an
optional cheap check that the rewrite doesn't contradict the harness (an LLM-judge
pass, or simply: reference solution must still be a valid answer). ~204 base
prompts × 4 registers ≈ **+800 diverse pairs**, and the same technique applies to
FIM/wtest prompts.

**Forward fix in the loop:** rotate the few-shot exemplar in `prompts.ex` (currently
hard-pinned to task 001) across 5–10 solved tasks of different shapes, and add an
explicit style-axis instruction to `Prompts.base` and `variation_prompt.md` (which
today says "differ just a little bit" — replace with named axes: domain, API shape,
prompt voice, difficulty).

### 5.2 Multi-turn conversations

Beyond §4.2's naturally-arising repair dialogues: script 2–3-turn extensions of
existing tasks ("now add TTL support", "now make it distributed-safe") where each
turn's completion is a *variation* dir you already have (many variation families are
literally extensions of the base). Stitching existing verified pairs into
conversations is mostly deterministic curation.

### 5.3 Keep the loop running — 917 ideas remain

At the observed ~7 dirs/idea (base + ~1.5 variations + ~3 sfim + wt + ~3 tfim), the
remaining backlog is worth **~6,000+ dirs**. But fix the coverage skew first (§7) so
the next 6,000 aren't more GenServers.

---

## 6. Code audit — `lib/` and `scripts/` findings

### 6.1 Correctness bugs (fix before scaling)

| # | Finding | Location | Fix |
|---|---|---|---|
| 1 | **`green?` counts skipped/excluded tests — worse than docs/05 #19 recorded.** ✅ DEMONSTRATED (`docs/prototypes/proto_vacuous_green.exs`): an all-`@tag :skip` harness with FALSE assertions grades `passed=2, overall=1.0` and `green? == true`. Root cause is double: `green?` never checks `tests_passed`, **and** `runner.ex:346` computes `tests_passed = total - failures - excluded` without subtracting ExUnit's separate `skipped` count — skipped tests are reported as *passed* | `evaluator.ex:107-112` + `runner.ex:342-352` | subtract `skipped` in `runner.ex` (destructure it from `ExUnit.run/0`) **and** require `tests_passed > 0` in `green?` — the second fix alone is defeated by the first bug |
| 2 | **No fixed ExUnit seed**: `ExUnit.start(autorun: false, …)` without `seed:` → random test order + random StreamData seeds; a flaky harness can pass accept-grade then fail forever in `validate.exs`. ✅ confirmed: nothing anywhere in `lib/eval_task/` or the scripts sets a seed | `runner.ex:321` | `seed: 0` (or per-task fixed seed) |
| 3 | **Mutants "killed for the wrong reason"**: any non-green mutant grade — including *the mutant failing to compile* or a 120s timeout — counts `:killed`; the coverage gate can pass vacuously. (Nuance: a mutation that fails to *parse* returns the source unchanged, `mutation.ex:52-53,76-77`, and so conservatively grades `:survived` — the hole is compile-fail/hang mutants specifically) | `mutation.ex:170,185,214` (docs/05 #18, open) | require ≥1 test failure specifically |
| 4 | `GEN_ONLY=fim` (or any non-`backfill` value) silently means bases-only | `config.ex:130-135` | validate enum; docs/06 §11.5 also wants `wtest`/`tfim` scopes |
| 5 | `env_int` accepts junk (`GEN_LIMIT=5x` → 5) | `config.ex` | strict parse |
| 6 | `run_all.exs` prints PASS when `tests_total==0` or `tests_errors>0` (only `tests_failed` consulted) | `run_all.exs:112-113` | consult errors + total |
| 7 | **`dataset_stats.exs` computes wt_ pair size as prompt+solution, but the wt completion is the harness** — context-window stats for 203 examples are wrong | `dataset_stats.exs:77` | per-shape completion selection |
| 8 | `quality_shortfall` doesn't check `lines_over_98` / `sql_injection_risk` though the rubric scores them → accepted refs can still lose analysis points | `evaluator.ex:122-136` | add both checks |
| 9 | Multifile tfim gate is assertion-regex only (no mutation) — a vacuous `assert is_map(x)` block passes | `test_fim.ex:134-142` (docs/06 §11.2) | reduced mutant gate for bundles |

### 6.2 Wasted LLM calls / wasted compute

- **FIM selection + candidate calls are mechanically derivable** — see §4.6 (~2 calls
  per subtask → ~0–1).
- **Contract-violation repairs re-grade unchanged files**: when a fix reply violates
  the output contract, the attempt is consumed and the *identical* triplet is
  re-staged and re-graded, including the full per-fn mutation run
  (`cycle.ex:114-117`, `fim.ex:329-331`).
- **Variations are all-or-nothing**: 1 malformed triplet of 3 discards the whole
  (large) generation (`reply.ex:117-126`, `variations.ex:103-110`) — salvage valid
  `vN/` sets.
- **The entire `tasks.md` is inlined into every variation call**
  (`prompts.ex:188-189`) — prompt cost grows linearly with the catalog; pass idea
  titles only.
- **`warn_if_vacuous_seed` runs the full per-public-fn mutation gate (N eval
  subprocesses) on every backfill seed on every run** purely to emit a warning
  (`cli.ex:182-200`) — cache the verdict.
- **No negative cache for tfim/wtest rejects**: FIM has `logs/fim_rejected.jsonl`
  (`cycle_log.ex:119-147`) but tfim/wtest re-gate the same rejected blocks
  (reconstruct + isolation + mutants) on **every** backfill pass forever
  (`test_fim.ex:66-79`, `catalog.ex:240`) — extend the rejected-ledger pattern.
- `GEN_LIMIT` bounds only new bases, not backfill fan-out (`catalog.ex:171-185`;
  docs/05 #7, open).
- Usage ledger blind spot: `usage.jsonl` records only `{:ok,…}` calls
  (`cycle.ex:135-156`) — failed/refused/exhausted call cost is invisible in metrics.
- `errored?` skip keys on gitignored `logs/errors/` — a fresh checkout retries
  everything (`cli.ex:296`).

### 6.3 Scoring / analysis rubric weaknesses (`lib/eval_task/analysis.ex`)

- All checks are regex/`String.contains?`: `@moduledoc` inside a string/comment
  counts; one `@spec` anywhere satisfies "specs present"; the SQLi regex
  (`analysis.ex:61`) is single-line with obvious false positives (interpolation +
  `WHERE` in a log message) and false negatives (multi-line). Move to AST checks
  (`Code.string_to_quoted` + walk) — cheap and exact.
- Excluded tests **lower** the tests score (they stay in `tests_total`) while
  `green?` ignores them — inconsistent semantics with 6.1#1.
- `:fim` mode has only 3 analysis points → one 99-char line costs 0.067 overall;
  noisy for single functions.
- FIM reconstruction warnings (unused skeleton helpers etc.) are charged to the
  *candidate*'s compilation score — docs/05 observed green FIM solutions scoring 0.0
  compilation. Attribute skeleton-origin warnings to the skeleton.
- wtest grading runs `:full` analysis on `solution.ex` (the module) though the
  candidate is the *harness* (`runner.ex:177-184`) — the analysis subscore judges the
  wrong file.
- ~~`credo` check stubbed to 2 free points~~ **STALE — verified refuted:** the
  rebuilt `analysis.ex` already dropped credo from scoring entirely (see the
  moduledoc note at `analysis.ex:16-19`; `checks/1` has no credo entry). The claim
  was true of the old `scripts/eval_task.exs` only. Wiring real credo remains a
  *possible enhancement* (it is still a dep), not a bug fix.

### 6.4 Brittleness / structural

- Variation slots hard-coded to 3 (b ∈ 2..4) in `catalog.ex:235,250`,
  `variations.ex:57,63` — make it a knob to fan out further.
- tfim carving is 2-space-indent line-scanning (`test_fim.ex:152-175`) — misses
  `describe`-nested and `property` blocks, and any nonstandard formatting; silently
  shrinks yield. Rewrite indent-aware or AST-based (unlocks §4.7).
- **Meta-prompt duplication**: the manual workflow prompts (`tasks/*.md`) and the
  loop's `prompts.ex` are separate copies that can drift — single-source them.
- `prompts.ex:13-17` reads the exemplar with a compile-time cwd-relative `File.read!`.
- `Opus.classify` usage-limit detection is string-sniffing (`opus.ex:26-27`);
  bounded post-docs/05 but still fragile to wording changes.
- `Evaluator.grade` depends on GNU `timeout` + repo-root cwd; a "no JSON but exit 0"
  result is indistinguishable from compile failure (`Jason.decode!` on `"{}"`).
- Truncation retry appends the reminder cumulatively across retries
  (`opus.ex:86-97`).

### 6.5 The loop harvests none of its intermediate artifacts

Confirmed: staging dirs destroyed on re-stage; repair transcripts only at debug level
in gitignored logs (deleted on later success); grader JSON gitignored; the JSONL
ledgers (`runs/usage/waits`) consumed by nothing except FIM-reject filtering. See
§4.2 for the fix — this is the roadmap's highest-value single change.

---

## 7. Coverage — realized vs. catalog vs. the real world

### 7.1 Realized vs. catalog by bucket

(Keyword-classified over title+body+section of both catalogs; realized column
verified against dir titles. ~few % boundary noise.)

| Bucket | Catalog ideas (pure+ext) | Realized ideas | Realized dirs |
|---|---|---|---|
| OTP/GenServer/process/ETS/caching/rate-limit | ~119 | **36** | ~700 |
| Business-logic contexts + dataset-analytics Enum-wrangling | ~150 | 3 | ~40 |
| Ecto | ~100 | 3 direct (+12 shared w/ Phoenix) | ~165 |
| JSON/CSV/serialization/encoding | ~85 | 4 | ~92 |
| Phoenix controllers/plugs | ~75 | 12 | ~180 |
| Data structures/algorithms/ETL | ~66 | ~17 | ~120 |
| Testing (ExUnit/Mox/StreamData/tools) | ~55 | 5 | ~19 |
| Telemetry/logging/observability | ~39 | 2 (both stdlib) | ~25 |
| Auth (all hand-rolled patterns) | ~37 | 5 (all stdlib) | ~50 |
| **LiveView** | **~35** | **0** | **0** |
| Protocols/behaviours/macros/metaprogramming | ~31 | 0 | 0 |
| Strings/regex/unicode | ~24 | 1 | 5 |
| Dates/times/cron | ~21 | 2 | 35 |
| Distribution/clustering (mostly single-node algo sims) | ~18 | 1 | ~31 |
| Crypto | ~17 | 2 | ~7 |
| **Channels/Presence/PubSub** | ~16 | **0** | 0 |
| Releases/config/feature-flags | ~15 | 1 | 5 |
| Files/IO | ~15 | 0 | 0 |
| **Nx/Explorer** | ~14 | **0** | 0 |
| CLI/escript/OptionParser | ~13 | 0 | 0 |
| **Broadway/GenStage/Flow** | ~12 | **0** | 0 |
| **HTTP clients (Req/Tesla/Finch)** | ~10 | **0** | 0 |
| NimbleParsec/parsers | ~9 | 1 | 5 |
| **Absinthe/GraphQL** | ~8 | **0** | 0 |
| **Oban** | ~8 | **0** | 0 |
| Umbrella/mix tooling | ~4 | 0 | 0 |
| **Ash** | **1** (and it's an "Ash-*style*" macro reimpl) | **0** | 0 |

### 7.2 Gaps in the catalog itself (the backlog doesn't cover these at all)

- **Ash**: 1 pseudo-idea. Ash runs on `Ash.DataLayer.Ets` with **no database** —
  resources, actions, changesets, validations, policies, calculations, aggregates,
  relationships are all testable in-BEAM. Easily 50+ ideas (define a resource;
  add a policy; write a custom change; migrate a context to Ash; debug a policy
  denial; Ash + Phoenix JSON API).
- **Bumblebee / Axon / Scholar**: **zero mentions anywhere.** Bumblebee's model
  downloads make hermetic harnesses awkward — prefer **Axon** (tiny nets trained with
  fixed seeds, deterministic assertions on loss/weights), **Scholar** (classical ML,
  fully deterministic), and `Nx.Defn`. Nx/Explorer overall have only ~14 ideas
  despite `nx` and `explorer` being installed deps; the 63 "dataset-analytics"
  Enum-wrangling ideas are natural Explorer rewrites.
- **Oban**: ~8 ideas, not a dep. Oban's **Lite engine runs on SQLite** via
  `ecto_sqlite3` — which the Phoenix host kit already uses — so real Oban
  worker/uniqueness/retry/cron/testing (`Oban.Testing`) tasks need no Postgres.
- **Absinthe**: ~8 ideas, not a dep. Schemas execute via `Absinthe.run/3` with no
  server — very harness-friendly (queries, mutations, dataloader, middleware,
  subscriptions with PubSub).
- **Auth libraries**: the 37 auth ideas are all hand-rolled JWT/TOTP/session/RBAC.
  Joken (0 mentions), Guardian (2), Pow (0), bcrypt/argon2 (~1), and the
  `phx.gen.auth`-style flow are absent as *libraries*. Daily auth work is library
  integration, not HMAC-from-scratch.
- **LiveView modern surface**: the 35 ideas are older mount/handle_event style —
  HEEx, `Phoenix.Component`, function components, LiveComponent, streams,
  `live_session`, JS commands: 0 mentions.
- Also absent/thin: umbrella apps (0), `mix release`/runtime.exs/config providers
  (~0), Dialyzer/typespec workflows (0), gettext/i18n (~2), genuine
  macro/DSL-*authoring* (`defmacro`: 0 mentions despite a ~31-idea "metaprogramming"
  bucket), real multi-node distribution (`:global`, libcluster — the ~18
  "distribution" ideas are single-node simulations), websocket clients, Mox-centric
  testing workflows (~3–4 real ones in a 55-idea testing bucket).
- **Structural bias**: large parts of the external catalog (Parts A/B/C) are
  **"Mini X" reimplementations** (Mini Oban, Mini Absinthe, Mini Guardian, Mini
  Finch…) rather than **use-the-library** tasks. Reimplementation teaches algorithms;
  daily developer work is idiomatic library usage, debugging, and migration. Both
  belong in the dataset, but the balance currently tilts hard toward reimplementation.

### 7.3 Dependency audit (`mix.exs`)

| Dep | Status |
|---|---|
| jason | used by 145 dirs |
| phoenix (+plug) | 43 / 99 dirs |
| ecto_sql | 61 dirs |
| nimble_csv | 17 · decimal 7 · phoenix_pubsub 6 |
| stream_data | **2 dirs only — thin** (property-based testing is a great task family) |
| **req** | **0 uses** |
| **nx** | **0 uses** |
| **explorer** | **0 uses** |
| **phoenix_live_view** | **0 uses** |
| **mox** | **0 uses** |
| plug_cowboy | 0 task uses (Plug.Test needs no server) |
| postgrex | 1 nominal consumer (017_001) whose grading is skipped |
| ecto_sqlite3, credo | infra only (host kit / scoring) |

> **Measurement caveat (verified):** the "used by N dirs" counts are bare-word
> mentions across *any* file in a dir, mostly prompt prose. Actual *code-file*
> usage is much lower: jason 57 dirs, ecto 23, nimble_csv 6, **phoenix 2,
> decimal 1, phoenix_pubsub 0** (all six pubsub "uses" are prompt-text mentions).
> Real library-usage coverage is even thinner than the headline numbers suggest.

**Deps to add** for catalog expansion — every in-BEAM test story below was
fact-checked against current docs (2026-07):

- `oban` — ✅ `Oban.Engines.Lite` (SQLite via `ecto_sqlite3`, which the host kit
  already uses) since Oban 2.14; cron, unique jobs, scheduling all work; the
  notifier auto-switches to PG-free mode; `Oban.Testing` `:inline`/`:manual` modes
  don't even touch the DB. Keep queue concurrency modest (SQLite write locking).
- `ash` — ✅ `Ash.DataLayer.Ets` covers actions/changesets/policies/calculations/
  relationships/aggregates with **no database**, with one documented limitation:
  **no transactions** (so `require_atomic?`/transactional-hook tasks behave
  differently than on Postgres). Ash 3.x needs Elixir ≥1.15 — fine. Compile-heavy
  dep tree (spark, reactor) slows first build.
- `absinthe` — ✅ `Absinthe.run/3` executes queries/mutations incl. middleware and
  dataloader with no HTTP; subscriptions additionally need an
  `Absinthe.Subscription.Pubsub` module in the supervision tree (still hermetic).
- `gen_stage`/`flow`/`broadway` — ✅ `Broadway.DummyProducer` +
  `Broadway.test_message/3` push messages through real pipelines fully in-BEAM;
  use `start_supervised!` and generous `assert_receive` timeouts (batch timers).
- `axon` + `scholar` — ✅ both run on the default pure-Elixir `Nx.BinaryBackend`
  (EXLA is optional, not required); deterministic with explicit `Nx.Random` keys.
  **Constraint: toy scale only** (XOR-size nets, few epochs, small data) — the
  binary backend is very slow, so task specs must stay tiny.
- `joken` — ✅ pure-local JWT sign/verify via erlang-jose, no NIF, no network.
- password hashing — ⚠ `bcrypt_elixir` compiles a C NIF with a documented history
  of toolchain failures; **prefer `pbkdf2_elixir` (pure Elixir, same Comeonin
  API)** for hermetic tasks, or accept the build-essential requirement.
- `swoosh` — ✅ `Swoosh.Adapters.Test` delivers to the test process
  (`assert_email_sent`).
- HTTP-client mocking — ⚠ `Tesla.Mock` works but is soft-deprecated (docs
  recommend Mox); frame HTTP-client tasks around **Req's `plug:` option or
  Mox-style adapter injection** instead — which also finally exercises the unused
  `req` and `mox` deps.
- `phoenix_live_view` — ✅ `Phoenix.LiveViewTest` runs fully in-BEAM (no browser,
  no socket) but needs a **pre-baked fixture Endpoint** (secret_key_base +
  signing_salt config set before start) in the harness/host kit rather than
  per-task generation. ⚠ LiveView 1.1+ (this repo locks **1.1.28**) parses test
  HTML with `lazy_html`, a lexbor NIF — precompiled for common targets, cmake/C
  fallback otherwise. Highest setup cost of the additions; build it into the
  existing `phoenix_kit` pattern (`lib/eval_task/phoenix_kit.ex`).

---

## 8. How to generate idea sets that cover the whole space

Stop free-associating flat lists; drive generation from a **coverage matrix**:

- **Rows**: library/domain (stdlib, OTP, Phoenix, LiveView, Ecto, Ash, Oban,
  Absinthe, auth, Req, Nx/Axon/Scholar, Explorer, Broadway/GenStage, telemetry,
  Mox/StreamData, mix/releases, macros, …).
- **Columns**: task *type* — build-from-spec / **debug** / **refactor** / extend /
  write-tests / **explain-review** / **migrate-version** / configure-integrate.
- **Third axis**: difficulty (single function → module → multi-module feature) and
  prompt register (§5.1).

Then:

1. Encode the matrix in a machine-readable file (e.g. `tasks/coverage.yaml` mapping
   each idea number to cell coordinates) and make `dataset_stats.exs` report
   **fill-rate per cell** — gaps stay visible forever and idea-generation prompts
   can literally target empty cells ("give 10 ideas for LiveView × debug × medium").
2. **Mine real-world sources for raw material** instead of free association:
   - **HexDocs guides + library test suites** — each guide section and each test file
     of Phoenix/LiveView/Ecto/Ash/Oban is a ready-made, verifiable task seed.
   - **Elixir Forum question titles** — the true distribution of daily developer
     pain (great for the vague/bug-report registers).
   - **Exercism's Elixir track** — 100+ small verified exercises.
   - **Library changelogs/upgrade guides** — migration tasks ("port this from
     LiveView 0.20 to 1.0", "Ecto 2→3 patterns") are high-value daily work with
     near-zero representation anywhere.
   - **Popular OSS Elixir repos' closed issues/PRs** — real bug→fix pairs.
3. Keep the "Mini X" reimplementations (they teach algorithms and are
   dependency-free) but explicitly pair each with **use-the-real-X** counterparts.

---

## 9. Prioritized roadmap

**Phase 1 — protect the gates (hours)**
1. ✅ **DONE 2026-07-03** — `green?` + skipped-as-passed (§6.1#1), fixed ExUnit
   seed (§6.1#2), mutant kill-reason (§6.1#3), plus the same holes found and fixed
   independently in `validate.exs`. Full description: `docs/08`. Corpus re-swept:
   FIM mutation all-genuine.
2. ✅ **DONE 2026-07-03** (`docs/09` §1–2) — Finding A completed (incl. FIM
   skip-gating, beyond the drafted patch; 017_001 now drops out of backfill
   entirely) and Finding E base entries 16–25 added + verified.
3. ✅ **DONE 2026-07-03** (`docs/09` §3–4) — tfim negative cache
   (content-hash-keyed `tfim_rejected.jsonl`) + `warn_if_vacuous_seed` verdict
   cache (`seed_verdicts.jsonl`).

**Phase 2 — deterministic multiplication (days) → ~+3,000–4,000 examples, zero LLM**
4. `GEN_TFIM_MAX_PER_TASK=10` + describe-nested/`property` carving → tfim 579 →
   ~1,900 (cap-10, measured) + up to 452 describe-nested = **~2,300 upper bound**
   before isolation-gate attrition.
   ✅ **Cap raised to 10 (now the default) 2026-07-03** (`docs/09` §3); the next
   backfill pass mints the top-up. Describe-nested/`property` carving still open.
5. Attempt capture in `Cycle.run` + `scripts/mint_repairs.exs` (§4.2).
   ✅ **FULLY DONE 2026-07-03**: capture (`docs/08` §4) + the mint script
   (`docs/09` §9 — double-verified pairs, add-only, graded 1.0 end-to-end).
6. `scripts/mint_mutant_repairs.exs` (§4.3), de-doc pairs (§4.4), inverse pairs (§4.5).
7. ✅ **DONE 2026-07-03** (`docs/09` §7) — dataset_stats wt pair sizing fixed
   (completion = harness), plus run_all PASS honesty.

**Phase 3 — diversity (days)**
8. Prompt-register rewriting over the existing corpus (×3–5 on 204 base prompts, then
   FIM/wtest) (§5.1).
9. Rotate few-shot exemplars + style axes in `prompts.ex` / `variation_prompt.md`.
10. Alternate-model runs → negative/preference data (§4.8).

**Phase 4 — coverage (weeks, loop does the work)**
11. Add deps: `oban`, `ash`, `absinthe`, `joken`, `bcrypt_elixir`, `gen_stage`,
    `broadway`, `nimble_parsec`, `axon`, `scholar`, `swoosh`, `tesla` (§7.3).
12. Extend the catalogs against the coverage matrix (§8) — LiveView first (dep
    installed, 35 ideas waiting, `Phoenix.LiveViewTest` is in-BEAM), then Ecto-deep,
    Oban, Ash, Absinthe, auth-libraries, Nx/Axon/Scholar, channels/presence.
13. Deterministic sfim (§4.6) so FIM top-up stops consuming LLM budget.
14. Keep the loop running on the remaining 917 ideas (~6,000+ dirs at observed
    ~7 dirs/idea).

**Rough sizing:** Phases 1–3 alone take the corpus from ~1,400 to **~7,000–9,000
examples** with materially better stylistic and framing diversity, before the loop
generates anything new; Phase 4 is the path to a 5-figure corpus that actually spans
daily Elixir work.

---

## 10. Cross-references

- docs/03 §12–13 — evaluator known issues (KI-9 SQLite-vs-PG `on_conflict`; 017 PG kit).
- docs/05 — loop audit; open items #7, #13, #16, #17, #18, #19 are folded into §6 above.
- docs/06 §11 — deferred multiplication items (describe-nesting, tfim_max, multifile
  tfim gate, wtest/tfim benchmark caveat, `GEN_ONLY` scopes) — all folded into §4/§6.
- BACKFILL_PROGRESS.md — Findings A–E; Phase 1 backfill was at seed 52/125 with 209
  accepted at last checkpoint (C8); Phase 2 (verification) not started.

---

## 11. Verification log (2026-07-03)

Every load-bearing claim in this document was adversarially re-verified against the
live repo; the four key §4 mechanisms were prototyped end-to-end against the real
evaluator. Prototype scripts live in `docs/prototypes/proto_*.exs` (runnable via
`mix run` from the repo root). Outcome summary:

### 11.1 Prototypes — 4/4 viable

| Mechanism | Prototype | Result |
|---|---|---|
| §4.3 mutant-repair | `proto_mutant_repair.exs` | ✅ mutant of `call/2` fails 14/15 with captured failure messages; repair prompt assembled; gold re-grades 1.0. Caveat: `raise`-mutant messages are uniformly `"MUTATION"` — add subtler operators for realistic diagnostics |
| §4.4 de-doc pairs | `proto_dedoc.exs` | ✅ 3/3 stripped modules stay green; overall 1.0 → 0.85–0.87 (docs are the exact training delta); bad strips self-filter via grading |
| §4.6 deterministic sfim | `proto_det_sfim.exs` | ✅ multi-clause `handle_call/3` carved with zero LLM calls; evaluator detects `shape=fim`, reconstructs, 15/15. Fix for production: single stub for all clauses (splice leaves per-clause stubs dangling) |
| §4.1 tfim yield | `proto_tfim_yield.exs` | ✅ production carver counts 3,003 blocks (median 14); **cap-3 predicts 582 vs 579 actual**; cap 10 → 1,897; cap 15 → 2,514 |
| §6.1 #1 vacuous green | `proto_vacuous_green.exs` | ✅ bug demonstrated: 2 `@tag :skip` tests with false assertions → `passed=2, overall=1.0, green?=true` |

### 11.2 Code-audit claims (§6) — 17/18 confirmed at the cited lines

- **Confirmed:** every §6.1/§6.2 item except as noted; line drift was ±1 at worst
  (`catalog.ex:235`, corrected in place).
- **Understated (now corrected in §6.1 #1):** `runner.ex:346` counts ExUnit
  *skipped* tests as **passed** (`total - failures - excluded`, `skipped` never
  subtracted) — so the originally proposed `tests_passed > 0` fix alone would NOT
  catch an all-`@tag :skip` harness. Both fixes are required.
- **Refuted (now corrected in §6.3):** the "credo stubbed to 2 free points" claim
  was stale — the rebuilt `analysis.ex` dropped credo scoring (`analysis.ex:16-19`).
- **Nuanced (§6.1 #3):** unparseable mutations conservatively grade `:survived`;
  the vacuous-kill hole is specifically compile-fail/hang mutants.
- Bonus confirmations: `run_all.exs` summary `full_pass` requires `tests_total > 0`
  but still ignores `tests_errors`; the truncation-reminder accumulation also exists
  in `fim.ex:355-360` (bounded to 2).

### 11.3 Coverage claims (§7) — all confirmed exactly

- The 83 realized idea numbers match the doc's list **set-exactly** (both
  directions empty diff).
- Zero-usage deps confirmed at 0 task dirs: `Req.`, `Nx.`, `Explorer.`,
  LiveView/`~H`/`Phoenix.Component`, `Mox`.
- Catalog blind spots confirmed: Bumblebee/Axon/Scholar 0 mentions; `defmacro` 0;
  umbrella 0; Joken 0; Pow 0; Guardian 2 (both inside idea 345 "Mini Guardian");
  Ash = idea 867 only ("Ash-*Style*" macro reimplementation) — plus an **empty stub
  heading `### Ash Framework Patterns`** at `tasks.md:2857` (among other empty stubs:
  Telemetry, Commanded, Mox, LiveBook) confirming these were recognized as gaps but
  never filled.
- tfim saturation: 579 = 193 parents × exactly 3 — yield is cap-limited, not
  gate-limited. 11 base tasks produced no tfim at all (017/018×3/019/037/072/074/
  075/087/096).
- One measurement honesty note added to §7.3: dep-"usage" counts are any-file word
  mentions; code-file usage is lower (phoenix 2 dirs, decimal 1, phoenix_pubsub 0).

### 11.4 Ecosystem claims (§7.3 additions) — all 9 fact-checked true, 3 with caveats

Verified against current hexdocs (details inline in §7.3): Oban Lite ✅ (since
2.14; cron/unique work; `Oban.Testing` engine-agnostic), Ash ETS ✅ (**no
transactions**), `Absinthe.run/3` ✅ (subscriptions need a Pubsub module),
Broadway DummyProducer ✅, Axon/Scholar on BinaryBackend ✅ (**toy scale only**,
EXLA not required), Swoosh Test ✅, Tesla Mock ⚠ (soft-deprecated → prefer
Mox/Req-plug), LiveViewTest ✅ (fixture Endpoint + `lazy_html` NIF on the locked
LV 1.1.28), Joken ✅ / bcrypt_elixir ⚠ (C NIF → prefer `pbkdf2_elixir`).

### 11.5 Net effect on the roadmap

No phase changes. Two number revisions: tfim projection is ~1,900 at cap 10 /
~2,514 at cap 15 (upper bounds), and Phase 2's total remains ~+3,000–4,000 once
mutant-repair (~1,000), de-doc (~200), inverse (~200), and repair pairs (hundreds,
growing) are included. One prescription strengthened: the §6.1 #1 fix must touch
`runner.ex` (subtract `skipped`) as well as `green?`.
