# 14 — Handover & Work Register

**Written 2026-07-13. This file assumes you know nothing about the recent work.**
Read it top to bottom and you can take over: what the project is doing right now,
what every tool and ledger is for, what is done, what is open, what it costs, and
what will bite you if you skip a step.

Reading order for a cold start: `/STATUS.md` (one screen: current mode) → **this
file** (the register) → `docs/12` (the quality standard S1–S12 + the catch-up
plan) → `docs/13` (the data-extension research: new shapes and their evidence).
`docs/10` and `docs/11` are historical campaign logs — read only when archaeology
is needed.

---

## ⭐ START HERE — the exact state, and the exact next action

**Verified 2026-07-13 ~18:0x (updated after the scrutiny session — quality
chains 1+2, reject-ledger audit, spot verify, semantic-floor close-out).
Everything below was re-run, not remembered.**

### The machine is idle and healthy

| check | command | expected output (verified 2026-07-15) |
|---|---|---|
| nothing running | `pgrep -af "generate.exs\|validate.exs\|screen_blind\|strengthen\|enrich"` | *(no output — your own shell may self-match; ignore the `bash -c` line)* |
| clean tree, pushed | `git status --porcelain` / `git status -sb` | *(empty)* / `## main...origin/main` in sync |
| no work owed | `mix run scripts/work_status.exs --counts` | `variations=0 fim=0 write_test=0 test_fim=0 bugfix=0 adapt=0/249` |
| factory tests | `mix test` | `327 passed` |
| temp-path lint | `mix run scripts/lint_temp_paths.exs` | `60 shared-path harness(es), 0 violations ✓` |
| corpus format | `elixir scripts/format_corpus.exs --check` | `0 deviating, 0 errors` |
| tfim embeds | `mix run scripts/resync_tfim_embeds.exs` | `%{unchanged: 3267}` |
| bugfix embeds | `mix run scripts/resync_bugfix_embeds.exs` | `%{unchanged: 960}` |
| wt_ embeds | `mix run scripts/resync_embeds.exs -- --wt-all` | `%{unchanged: 331}` |
| adapt embeds | `mix run scripts/resync_adapt_embeds.exs` | `%{unchanged: 249}` |
| fim/wt_ fences | `elixir scripts/check_embeds.exs` | `1322 clean, 0 reflow, 0 drift` |
| export contract | `mix run scripts/export_dataset.exs -- --selfcheck` then `--check` | `all 8 planted violations detected` / `export check: OK ✓` |
| retro §5.2 screen | `mix run scripts/rescreen_repaired.exs -- --report` | `59 PASS / 15 entailed / 0 open / 0 unscreened` |

> Postgres note: `017_001` is the corpus's only `db: :postgres` task and it
> goes loudly RED (not skipped — by design) when the DB is down. A full sweep
> on a DB-less machine will always report exactly that one failure; the remedy
> is `docker compose up -d db`.

**If any of those differ, something changed after this file was written — diagnose
that before starting new work.** (A resync gate showing `would_resync` means a
parent was edited and its children were not; run the same command with `--apply`.)

### Pick your next action

**A. The §5.2 retro screen and the semantic floor are BOTH DONE (2026-07-13).**
Retro screen: 59 PASS / 15 entailed / 0 open (6 prompt gaps found & fixed en
route — §5.1 item 1). Semantic floor: 16 of 20 fixed, 4 at documented ceilings
(§5.3). What remains before Phase 3 is **decisions, not work**: Kamil's §5.2
loop-wiring sign-off (docs/12 §5.2.1 — the retro evidence now strongly supports
it), the §4.2 sign-offs, and the 4-command systemd timer install.

**B. If you want to extend the dataset → docs/13 §2.** Next up is *adaptation
pairs* (brownfield editing — the one register the corpus lacks). The RED-gate
measurement is DONE: **249/249 pairs mintable** (§5.4). What remains is the
`:adapt` registry entry + runner — deterministic, zero LLM.

**C. Before ANY training run → the export contract (docs/13 §3.1).** Within-family
text overlap is 91.7% by construction; a naive random split leaks and invalidates
your eval. This is not optional.

**D. After ANY gate repair → audit the ledgers that gate wrote** with
`scripts/reverify_rejects.exs` (§5.0c). On 2026-07-13 this found 15 unsound
tfim rejects blocking 7 mintable units.

### The three things that will bite you if you skip them

1. **After editing ANY parent `prompt.md` or `test_harness.exs`**, its children are
   stale. Run the cascade — see §7 "After ANY parent-prompt edit" — or CI will fail.
2. **Never poll with `pgrep -f "<pattern>"`.** A wait-loop's own command line
   contains the pattern, so it matches itself and waits forever. Poll a PID
   (`while kill -0 $PID; do sleep 30; done`). This cost ~100 minutes of dead time.
3. **Launch long jobs with `scripts/run_detached.sh`** (it `setsid`s). A bare
   `nohup … &` inside a tool call does not reliably survive.
4. **RUNTIME warnings in improvement-tool logs (e.g. `Range.new/2 … step of
   -1`, `map.field notation … :not_found.id()`, tagged `/tmp/gaps_*.ex`,
   `/tmp/strn_*.ex`, or `.gen_staging/...`) come from DELIBERATELY BROKEN
   staged code** — semantic mutants and blind-solver candidates being
   graded (a mutant that returns `:not_found` where a map belongs turns
   `record.id` into the deprecated `:not_found.id()` right before the test
   kills it) — not from the corpus. The runtime sibling of the 2026-07-12
   compile-spill finding. The corpus itself is warning-free (the perfect
   gate proves it); verify with one scoped eval before chasing them, and do
   NOT silence them in the evaluator — that edit changes the gate sha and
   invalidates every gate-sha-keyed measurement row (rule-7 corollary).

### Where the evidence lives

- **What the loop did:** `logs/runs.jsonl` (every accept/reject, ever).
- **What each improvement tool did:** `logs/strengthen_harnesses.jsonl`,
  `logs/enrich_prompts.jsonl`, `logs/bugfix_rejected.jsonl`,
  `logs/semantic_mutants.jsonl`, `logs/screen_blind.jsonl` (+ `screen_triage.jsonl`).
  §4 explains every row and, crucially, **what content key makes it valid**.
- **The last runs' console output:** `logs/topup_20260713.log`,
  `logs/strengthen2.log`, `logs/final_pass.log`, `logs/rescreen_enriched.log`.
  (Old `logs/backfill_phase2.log` is the Phase-2 history.)

---

## 0. Sixty-second orientation

The repo is a **factory that produces a verified Elixir SFT dataset**, not just a
dataset. Two halves:

- **`lib/` + `scripts/generate.exs`** — the generation loop. It creates task
  units and only keeps them if they pass hard, deterministic gates.
- **`tasks/`** — the corpus: 5,860 directories, every one of which has been
  graded green by the real evaluator.

Everything else (`scripts/*.exs`) is a **tool with a ledger**: a repeatable,
resumable job that measures, repairs, or extends the corpus and writes what it
did to `logs/*.jsonl`.

**The three invariants that make this work.** Violate them and the corpus rots
silently — every incident in §6 traces back to one of these:

1. **Every unit is machine-verified.** No judge, no vibes. If a gate cannot prove
   a unit, the unit does not ship.
2. **Prompt-only solvability (S6).** A solver reading *only* `prompt.md` must be
   able to pass the harness. A test that pins behavior the prompt never states is
   a bug in the *prompt*, not a stronger test.
3. **Derived files must be regenerable, and gates must prove they still are.**
   Any child that embeds a parent's text has a resync tool AND a standing gate.

---

## 1. Corpus inventory (measured 2026-07-13)

| shape | dirs | what it is | prompt contains | gold is |
|---|---|---|---|---|
| `NNN_00b_slug_01` (roots) | **332** | base tasks + variations | the spec | `solution.ex` |
| `NNN_00b_slug_0N` (fim) | **991** | code fill-in-the-middle | module with ONE function `# TODO` | that function |
| `wt_…` | **331** | "write the tests" | module + parent spec | the gold harness |
| `tfim_…` | **3,267** | test fill-in-the-middle | module + harness with ONE `test`/`property` blanked | that test block |
| `bugfix_…` | **960** | debugging | spec + a module with ONE bad line + the REAL failing ExUnit output | the correct module |
| `adapt_…` | **249** | brownfield adaptation (docs/13 §2.1) | the family BASE's gold as starting point + the variation's spec | the variation's module |
| `repair_…` | **17** | repair from a real failed attempt | the original request + the failed code + its report | the accepted fix |
| **total** | **6,147** | | | |

`mix run scripts/work_status.exs` prints what each work type still owes, live from
disk. It is the source of truth for "what is left to generate", not any doc.

---

## 2. The gates (what protects the corpus)

**CI (`.github/workflows/validate.yml`) — every push:**

| gate | protects against |
|---|---|
| `mix format --check-formatted` | non-canonical **lib/test** code |
| `mix compile --warnings-as-errors`, `mix test` | broken factory (296 tests) |
| `validate.exs --mutants` | a harness that passes a fully-gutted solution |
| `format_corpus.exs --check` | non-canonical **corpus** files |
| `resync_tfim_embeds.exs` (dry) | tfim prompts drifting from their parent harness |
| `resync_bugfix_embeds.exs` (dry) | bugfix prompts embedding a stale parent spec |
| `resync_embeds.exs --wt-all` (dry) | wt_ dirs drifting from their parent (module, harness, spec) |
| `resync_adapt_embeds.exs` (dry) | adapt_ dirs drifting from their parents (base gold, variation prompt/gold/harness) |
| `check_embeds.exs` (+ `--self-test`) | fim/wt_ module fences drifting; the self-test proves the checker is not vacuous |
| `export_dataset.exs --selfcheck` then export + `--check` | a train/val split that leaks families, a write_test gold trap, dropped/duplicated rows, metadata drift (docs/16) |
| weekly / manual | full `validate.exs` (perfect score) and `--fim` sweeps |

**Pre-push hook (`.githooks/pre-push`, enable with `git config core.hooksPath .githooks`):**
the same checks, scoped to touched families, plus the corpus-wide embed gates.

> **If a gate fails, the answer is never "loosen the gate".** Every gate in this
> table was added because something rotted silently without it.

---

## 3. The tools (all in `scripts/`, all ledgered, all resumable)

Everything below is safe to kill mid-run: state lives in `logs/*.jsonl`, keyed by
content sha, so a re-run resumes and never redoes finished work.

### Generation
- **`generate.exs`** — the loop. `GEN_ONLY=backfill` tops up derivatives for
  existing seeds; without it, it also creates new base tasks from `tasks/tasks.md`.
  **Always launch detached:** `scripts/run_detached.sh logs/<name>.log mix run scripts/generate.exs`.
  (`nohup … &` inside a tool call does **not** reliably survive. Use `run_detached.sh`,
  which `setsid`s.) It rides out token-limit windows by sleeping 15 min and retrying,
  forever, by design.
  Useful env: `GEN_ONLY=backfill|bases`, `GEN_EXCLUDE_SEEDS=016_001,…` (skip known
  failers), `GEN_SKIP_BUGFIX=1`, `GEN_LIMIT=N`.
- **`work_status.exs`** — what each work type still owes. `--counts` for one line.

### Verification (no LLM, free)
- **`validate.exs`** — the gate suite. Default = perfect score. `--mutants`,
  `--fim`, `--per-fn-mutants`, `--semantic-mutants` (measures assertion
  tightness), `--decontam` (benchmark overlap).
- **`audit_bugfix.exs`** — six-property audit of `bugfix_` units (bug reproduces,
  report matches, gold passes, gold ≡ parent, exactly one line differs, spec
  included). Run it on any random sample after a mint.
- **`classify_survivors.exs`** — for a below-floor family, are the surviving
  mutants **observable** (a real gap) or **internals-only** (an unreachable
  ceiling)? See §5.3 — this decides whether a family is even work.
- **`check_embeds.exs`**, **`resync_*_embeds.exs`**, **`format_corpus.exs`** — the
  drift/format gates (dry by default; `--apply` to fix).

### Improvement (LLM, costs tokens)
- **`enrich_prompts.exs`** — rewrites a too-vague `prompt.md` so it *documents the
  behavior the reference module actually implements*. Five gates: no test-name
  leak, no ≥4 verbatim module lines (a spec must not hand over the answer),
  public API preserved, strictly additive, and a **blind solve** against the
  existing harness. Cascades to `wt_` + `bugfix_` children automatically.
- **`screen_blind_solve.exs`** — the canonical S6 screen (ledger of record).
  **Run it after any prompt edit** — the ledger is keyed by prompt sha, so an
  edited prompt is "unscreened" until you do.
- **`strengthen_harnesses.exs`** — adds tests to a weak harness. Gates: add-only
  (existing test blocks must stay byte-identical — tfim golds carve them!),
  reference green, zero warnings, house/harness lints, whole-mutant killed,
  semantic re-measure ≥ floor and ≥ before, and a **blind gate**. Propagates to
  wt_/tfim children and **restores the original harness** if anything fails.
- **`rescreen_repaired.exs`** — retro blind screen of accepts that went through a
  repair loop (see §5.1).
- **`mint_repairs.exs`** — mints `repair_` units from captured attempt chains.
- **`close_gaps.exs`** — findings-seeded ADD-ONLY gap closer (strengthen mold);
  reads confirmed harness_gap findings from `logs/semantic_review.jsonl`.
  ⚠️ run `--go` SCOPED (`--only`) — six hand-closed families read as phantom
  todos forever (header comment lists them).
- **`semantic_review.exs`** — full-context semantic review per root + adversarial
  verify per finding (T2.2). `--single DIR --as label` runs positive controls.
- **`rubric_judge.exs`** — T2.4 3-axis rubric (docs/12 §6.4) over PASSING roots,
  two judge families (PoLL), per-axis agreement logged; deterministic stratified
  batch; `--single` control mode. Triage = both families ≤3 on the same axis.
- **`survey_adapt_redgate.exs`** — measures the adapt mint gate standalone (the
  in-loop runner re-measures drifted pairs itself).

### Export (the only path to training data)
- **`export_dataset.exs`** — docs/16. Family-atomic deterministic split,
  per-shape gold mapping, advisory weights, round-trip `--check` + `--selfcheck`
  (both in CI). Output `results/export/` is a build artifact, never source.

### Script disposition & testing (Kamil's ask, 2026-07-15)

Every script is one of two kinds, and the testing bar follows the kind:

**PERMANENT (steady-state infrastructure — must be tested):**

| script | safety net today |
|---|---|
| `eval_task` / `validate` / `run_all` / `generate` / `work_status` | thin CLIs over `lib/` — the 344-test suite is their coverage |
| `export_dataset` | CI `--selfcheck` (8 planted violations) + unit tests (`test/scripts/`: family/split determinism, shape-map totality, the write_test gold trap) |
| `resync_adapt_embeds` | `--self-test` in CI (plant → detect → heal → re-verify) + dry-run gate |
| `resync_tfim` / `resync_bugfix` / `resync_embeds --wt-all` | dry-run CI gates; **no self-tests yet — registered in STATUS as T-gates** |
| `check_embeds` / `lint_temp_paths` / `check_screen_freshness` | have `--self-test`, wired in CI |
| `format_corpus` | exercised on every push |
| `spot_verify.sh` / `reverify_rejects` | CONTEXT rule-8 standing audits; deterministic + ledgered |
| `rubric_judge` | positive-control-proven instrument + unit tests (agreement, reply contract, errored-row resume) |

Scripts are unit-testable via the load guard: `test/scripts/*_test.exs` set
`SCRIPTS_NO_AUTORUN=1` and `Code.require_file` the script, then test its
public `@doc false` functions; ledger/corpus paths are env-overridable
(`RUBRIC_JUDGE_LEDGER`, `CLOSE_GAPS_*`) so tests run in sandboxes.

**CATCH-UP (delete at the line, docs/12 §7.2 — no test investment beyond
protecting remaining use):** `strengthen_harnesses`, `enrich_prompts`,
`rescreen_repaired`, `mint_repairs` (as one-shot), `screen_blind_solve` +
`triage_screen` (after T1.1 flips + the CI evidence check), `close_gaps`
(resume logic IS unit-tested — it is actively finishing T2.4-T),
`survey_adapt_redgate` (superseded by `GenTask.Adapt.red_gate`, which lives
in lib WITH tests), `quality_chain*.sh`. `semantic_review` is kept until the
T2.2 full-pass decision, then Kamil decides its fate.

---

## 4. The ledgers (`logs/*.jsonl`) — what each one means

**The rule that cost us four days: a ledger row is only valid for the content it
was measured on.** Every row must carry a content key, and every consumer must
check it.

| ledger | rows | keyed by | meaning |
|---|---|---|---|
| `runs.jsonl` | 5,260 | — | every accept/reject the loop ever made (provenance) |
| `screen_blind.jsonl` | 415 | **prompt sha** | S6 verdicts. Edit a prompt → it is unscreened again |
| `screen_triage.jsonl` | 87 | task + prompt sha | human/LLM triage of S6 REDs (`entailed: true` = prompt was fine, solver was weak) |
| `semantic_mutants.jsonl` | 660 | **solution + harness sha** (since 07-13) | assertion-tightness measurements. **Rows before 07-13 have no keys — treat as STALE-UNKNOWN** |
| `strengthen_harnesses.jsonl` | 58 | harness sha (success) | one row per family per attempt |
| `enrich_prompts.jsonl` | 18 | prompt sha (success) | one row per prompt per attempt |
| `bugfix_rejected.jsonl` | 444 | **solution + harness sha** | mutants the harness cannot kill → not mintable. Strengthen the harness and they re-open automatically |
| `tfim_rejected.jsonl` / `fim_rejected.jsonl` | 21 / 1 | harness sha / — | permanently-rejected carve targets |
| `seed_verdicts.jsonl` | 487 | content sha | seed self-check (is the harness vacuous?) |
| `flaky.jsonl` | 41 | — | harnesses that needed a stability re-run |
| `semantic_review.jsonl` | 62 | task + 3 content shas + review sha | T2.2 review findings + adversarial verdicts (close_gaps reads `confirmed`) |
| `close_gaps.jsonl` | ~60 | harness sha before/after + gate sha | one row per gap-close attempt; `applied` rows key resume |
| `adapt_redgate.jsonl` | 326+ | base-solution sha + variation-harness sha | the adapt mint gate; `green_not_mintable` suppresses the unit, drifted shas re-measure |
| `rubric_judge.jsonl` | grows | task + 3 content shas + rubric sha | T2.4 two-family rubric verdicts; rows with a judge error re-run on resume |

---

## 5. THE WORK REGISTER — what is open, right now

### 5.0 Free work available immediately (no decisions, no tokens)

**None — the registry reads 0 pending across every work type** (2026-07-13
evening; the 8-unit top-up AND the 9 units below were minted and committed).
When strengthening adds tests or a reject-ledger purge re-opens candidates,
pending units reappear here automatically; the mint command is:

    GEN_ONLY=backfill scripts/run_detached.sh logs/topup.log mix run scripts/generate.exs

Cost: CPU only. Then batch-commit the new dirs and push.

### 5.0c Reject-ledger audit (2026-07-13 pm) — 15 unsound rows purged, +9 units

**The 074_x lesson repeated on the tfim ledger and was caught by auditing it.**
All 15 CURRENT `102_001` rows in `logs/tfim_rejected.jsonl` had been written
2026-07-11 05:42 by the pre-manifest-fix bundle gate (the docs/10 §5.13 class,
fixed 07-12) and never re-audited after the fix. Re-run through the real gate
chain (`scripts/reverify_rejects.exs`), every one passes today — the rows were
silently blocking mintable units. Purged (backup
`logs/tfim_rejected.jsonl.bak_20260713`); the next backfill minted **7 tfim
units on 102_001** (+2 new carvables on 063_004). The 3 CURRENT 073_001 rows
re-confirmed sound; 27/27 sampled bugfix rejects sound; the 1 fim reject kept.

**Standing audit tools (one-shot class, delete at the line):**
- `scripts/reverify_rejects.exs` — re-derives reject-ledger verdicts through
  the SAME gates that wrote them; ledger `logs/reverify_rejects.jsonl`.
  Run it after ANY gate repair (docs/12 §5.1.12 made executable).
- `scripts/spot_verify.sh` — deterministic random re-verification of ACCEPTED
  data (fixed shuf seed; 8 batches: numbered×perfect/mutants/fim, wt_×2, tfim,
  all repair_, bugfix six-property audit); ledger `logs/spot_verify.jsonl`.
  2026-07-13 result: **8/8 batches clean** (204 dirs re-verified).

### 5.0b Corpus defect found & fixed 2026-07-13 — flaky harness (102_002)

The post-top-up perfect sweep failed 2 dirs at `1/16 tests failed`, intermittently.
Root cause (two bugs, one on top of the other) in
`102_002_optimistic_concurrency_persisted_state_machine`:

1. Its migration test writes to a **non-sandboxed** SQLite repo (deliberately — it
   exercises the real migrator) and asserted `count == 1` for a **fixed** row id, so
   a leftover/concurrent row made it 2.
2. The real culprit: the repo's DB **filename used `System.unique_integer` alone**,
   which is unique only *within one BEAM* — and the validator runs **one BEAM per
   task in parallel**, so two concurrent evals could draw the same integer, share the
   same SQLite file, and corrupt each other. (`EvalTask.Runner.uniq_suffix/0` already
   knew this and includes `System.pid()`; the harness did not.)

Fixed both (row keyed to the run; DB file keyed to `System.pid()` + integer),
propagated to the `wt_` and `repair_` harness copies and the 10 tfim prompts, and
proved with **three consecutive parallel full-family sweeps: ALL PERFECT** (it
previously failed ~1 in 3).

**Follow-up DONE (2026-07-13):** the corpus was swept for the same class. Of 680
harnesses, **60 build a path in a shared directory**; two more were racy and are
now fixed:
- `102_003` — `System.unique_integer` with no `System.pid()` (the identical latent
  bug),
- `102_004` — a **completely FIXED** SQLite filename (`state_machine_test.sqlite3`),
  i.e. *every* concurrent eval of that family shared one database. Worse than the
  bug that started this.

The `031_*` family's `/tmp/does_not_exist_#{:rand.uniform(…)}` paths are exempt by
design: the file is *meant* not to exist, so a collision is harmless.

Both fixed, propagated to their `wt_`/`repair_` harness copies and 20 tfim prompts,
and proven with three consecutive **parallel** sweeps over all three DB-backed
families: ALL PERFECT.

**Standing gate added — `scripts/lint_temp_paths.exs`** (CI + pre-push): a harness
that builds a path under `System.tmp_dir!()` or `/tmp` must include
`System.pid()` alongside `System.unique_integer/1`. Self-tested (clean → planted
violation → detected → restored), so the gate is not vacuous. Deliberately-missing
paths are exempt.

**Rejected idea, recorded so nobody repeats it:** I nearly made
`resync_tfim_embeds` refresh a child's GOLD from its parent block (not just the
prompt). Don't. A gold legitimately differs from its parent block — the corpus
formats golds as fragments and enforces ≤98 columns on them, while a parent harness
is *not* column-gated, so golds carry deliberately shortened comments and assertion
messages. A blanket refresh would import >98-column lines and break the perfect gate
on 12+ dirs. If a parent test's *behavior* is edited, re-carve that one child's gold
by hand and check the ≤98 rule (as was done here).

### 5.1 Blocking Phase 3 — decisions only Kamil can make

| # | item | state | evidence | cost |
|---|---|---|---|---|
| 1 | **§5.2 accept-time blind screen for repaired bases** | **RETRO SCREEN DONE 2026-07-13 — design decision (wire it into the loop) still Kamil's** | The 22 never-screened repaired accepts were screened: final population reads **59 PASS / 15 FAIL-triaged-entailed / 0 open / 0 unscreened**. The screen caught **6 genuine prompt↔harness gaps, all fixed + cascaded + re-screened GREEN**: 102_002/102_003/102_004 (migration module name undocumented; 102_003 additionally had its GOLD defining the repo module its own prompt forbade — a repair-loop artifact — and an undocumented atom-deserialisation contract, each caught by successive screens), 626_004 (undocumented `:cleanup_tick` message), 101_003 (harness asserts `keys/1`, never in the prompt — the literal 101_002 class again). Every hit was a repaired accept: the gap class is real and recurring, which is the strongest argument yet for wiring the accept-time blind screen into the loop before Phase 3 | retro: spent; loop wiring: docs/12 §5.2.1 |
| 2 | **§4.2 sign-offs** (spot-review scope, prompt-monotony scope, semantic floor) | OPEN | The semantic-floor half is now *answered with evidence* (§5.3): the floor should be "kill rate among **observable** mutants", not a flat 0.5 | decision only |
| 3 | **Nightly-sweep systemd timer install** | STAGED, needs 4 commands | `scripts/systemd/nightly-sweep.service` | 5 minutes |

### 5.2 Phase 2 (derivative top-up) — **COMPLETE**

All work types read 0 pending at the end of the campaign (the 8 units in §5.0
appeared afterwards, as a *result* of strengthening). What was fixed to get there,
in case it recurs: bundle-parent fim (eval reconstructed bundles wrongly), macro
targets (`defmacro`-blind enumerators), variation distinctness (the prompt never
told the model which APIs were taken), describe-nested tfim carving, and
predicate-named targets (`\w` cannot match `?`/`!`).

### 5.3 The semantic floor (S8) — **CLOSED 2026-07-13: 16 of 20 fixed, 4 at ceiling, 0 open**

Final tally: the 13 below + **013_001 0.41→0.77** (hand-written: observe the
backoff schedule through the injected `:random`, which receives the clamped
delay — zero timing assertions, which is what the 3 automated attempts kept
tripping on), **063_004 0.47→0.94** (chain-strengthened through the blind
gate), **101_001 0.47→0.76** (hand-written: default-bucket quantization and
retention probed via clock + `:cleanup`; the model's 3 attempts all died on
the S9 lint because it imitated the `:sys.get_state` calls already present in
the April-era tests — grandfathered debt teaches the strengthener to cheat).

At ceiling, recorded and left alone: `041_001`, `041_003`, `023_002`, and —
**reversing this file's earlier "hardest real gap" diagnosis** — `077_001`:
all 15 of its survivors are AVL bookkeeping (heights, balance factors,
rotation thresholds, equal-start insertion side), proven behaviorally
IDENTICAL to the reference by public-API fuzzing over 32 adversarial case
groups. The classifier's `@internal` vocabulary now knows structural
bookkeeping (`height(`, `balance_factor`, `rotate_*`, `lh`/`rh`) and reads
077_001 as AT CEILING 0.96. **Method note: `classify_survivors` is a line
heuristic — before declaring a below-floor family a REAL GAP, fuzz its
survivors through the public API (the 077_001 scratch experiment pattern).**

*(original section, kept for the per-family history:)*

The recipe that works, and the order matters:
**enrich the prompt → canonical blind re-screen → re-strengthen the harness.**

Nine of the thirteen were only strengthenable *after* enrichment. The clincher:
`001_001`'s prompt **failed** the S6 blind screen in July; enriched (22 → 109
lines) it passes, and its harness went 0.47 → 0.87.

**The 7 that remain (classify first — `mix run scripts/classify_survivors.exs`):**

- **AT CEILING — not defects, do not "fix":** `041_001` (0.45, ceiling ≈0.82),
  `041_003` (0.48, ≈0.74), `023_002` (0.47, ≈0.53). Their surviving mutants change
  only internals (ETS flags, counter seeds/steps). The only way to kill them is a
  `:sys.get_state` reach-in, which the S9 lint forbids — and that is exactly what
  every strengthening attempt tried before being rejected. **Record the ceiling and
  move on.**
- **REAL GAPS — actionable:**
  - **`063_004_bounded_concurrency_concurrent_fetcher_01`** (0.47) — the strengthener's
    added test pins *zero-budget timeout* semantics (`a zero budget times out every
    source even when the fetches return instantly`) that the enriched prompt still
    does not state. **Action:** `enrich_prompts.exs -- --go --force --only
    "063_004*"` (the `--force` re-enriches an already-enriched prompt), making sure
    the rewrite documents what a `timeout: 0` budget does; then re-screen; then
    strengthen. ~4 calls. **Watch out:** its blind solves are noisy (bounded
    concurrency is hard for the solver) — if the gate says *INCONCLUSIVE: failed the
    ORIGINAL tests*, that is solver weakness, **not** a prompt defect. Retry, do not
    enrich again on that evidence.
  - **`101_001_sliding_window_counter_01`** (0.47) — last attempt died on the
    **add-only guard**: the model tried to MODIFY an existing test block (which would
    orphan that block's tfim gold). Nothing is wrong with the prompt (already
    enriched 35→110 lines, screened GREEN). **Action:** just re-run
    `strengthen_harnesses.exs -- --go`; it is stochastic. ~2 calls.
  - **`013_001_exponential_backoff_retry_worker_01`** (0.41) — writes tests its own
    reference FAILS, three attempts running, even with an enriched (15→60 lines),
    GREEN-screened prompt. **Do not spend more calls blindly.** **Action:** read
    `tasks/013_001_.../test_harness.exs` and `solution.ex` together and work out what
    the added tests keep asserting that the reference will not do (likely timing:
    the backoff schedule is probably not deterministically observable). It may be a
    *reference* bug, or a task that needs a fake clock (see 072_* for the pattern the
    corpus uses).
  - **`077_001_interval_tree_for_overlapping_range_queries_01`** (0.38) — the hardest.
    Reproducibly stalls at **0.42** across three attempts (before AND after
    enrichment), with **15 observable survivors** — so it is a genuine harness gap,
    not a ceiling. **Action:** hand-write the missing tests. The survivors are
    boundary/`±1` mutants on interval comparisons (`classify_survivors.exs -- --only
    "077_001*"` lists them exactly) — the harness needs cases where an interval
    *touches* a query bound (start == query_end, end == query_start) and where an
    interval is entirely inside/outside. Its sibling `077_004` was strengthened
    successfully — read that harness for the pattern.

### 5.4 Data extension (docs/13) — built, and next up

**Shipped and registry-live** (mints automatically for every future seed):
`:bugfix` (959 units) and property-block tfim carving.

**Ready to build, in priority order** (full designs + measured volumes in docs/13 §2):
1. **Adaptation pairs** — base gold + variation spec → "modify this module"; gate =
   the variation's existing harness; mint only where the base gold grades RED
   against it. Teaches brownfield editing (absent from every current shape).
   **RED-gate MEASURED 2026-07-13: 249/249 pairs RED** (237 test-fail, 12
   compile-fail; `scripts/survey_adapt_redgate.exs`, ledger
   `logs/adapt_redgate.jsonl`) — the mint gate is satisfied at maximum volume;
   what remains is the `:adapt` registry entry + runner.
2. **Multi-turn repair dialogues** — 86 attempt chains where every turn's wrongness
   is machine-graded. **PERISHABLE**: `logs/attempts/` is wiped when an id re-enters
   the loop. An archive exists (`logs/attempts_archive_20260712`); take another
   before any big run.
3. **Dedoc** (`@doc`/`@spec` stripped → "document this module"). Registry entry is
   already written as a comment in `lib/gen_task/work.ex`. **Blocked on a Dialyzer
   gate** — 019_001 proved shipped specs can lie, and wrong specs must not become
   training targets. Dialyzer needs `dialyxir` added to `mix.exs` (a lockfile call
   for Kamil).
4. Style-repair pairs (207 captured), cap lifts (~1,900 free tfim above the cap).

**BLOCKING PREREQUISITE before any training run:** the **export contract**
(docs/13 §3.1). Within-family text overlap is 91.7% *by construction* — a naive
random train/val split leaks and invalidates any eval. Needed: per-shape export
spec, family-keyed splits, a round-trip validator, and dedup/sampling weights.

---

## 6. Hard-won rules (each one is a scar; ignore at your peril)

1. **A ledger without a content key rots silently.** The 07-08 semantic rows
   survived a 07-09 harness campaign and misled the floor debate for four days.
   *Every* measurement row now carries `solution_sha` + `harness_sha`.
2. **"Take the best row" is not a policy — it hides regressions.** Use the
   *latest* row. And never measure a `wt_` dir separately: it is a byte-copy of its
   parent, so a separate row can only ever be a stale duplicate (this alone
   invented 10 phantom work items).
3. **Whatever an eval needs in order to classify a task must be staged with it.**
   The parent `manifest.exs` travels with every staged parent — its absence made
   tier-B families misdetect as tier-A and fail 0/N (four separate sites).
4. **Every gate criterion a generator is graded by must be stated in its prompt.**
   The distinctness gate rejected on public-API equality while the prompt only
   listed variation *names*; the warning gate said "N warnings — silence them"
   without naming them, and the fixer burned every retry guessing. Both cost days.
5. **When a gate is repaired, audit the ledger it wrote.** Nine macro targets sat
   "permanently rejected" because a broken gate could not see a macro kill.
6. **Regexes over Elixir identifiers must handle `?` and `!`.** `\w` cannot match
   them. This silently discarded every predicate-named fim target (`valid?/4`,
   `equal?/3` …) — the most idiomatic naming class in the language.
7. **A below-floor family is not automatically defective.** Classify its survivors
   first (§5.3): internals-only survivors mean it is at its ceiling, and any "fix"
   would be the internals-pinning test the S9 lint exists to reject.
8. **Never `git add -A` while a generation loop is alive** — it sweeps the loop's
   mid-run output into unrelated commits. Stage explicit paths; batch-commit loop
   output only after the run ends and the new dirs are validated.
9. **Detach long runs with `run_detached.sh`** (it `setsid`s — a bare
   `nohup … &` inside a tool call does not reliably survive). And when you wait
   for one, **poll its PID, never a pattern**:

       while kill -0 $PID 2>/dev/null; do sleep 30; done     # correct
       while pgrep -f "enrich_prompts" >/dev/null; do … done # WRONG: the wait
                                                             # loop's own command
                                                             # line contains the
                                                             # pattern, so pgrep
                                                             # matches ITSELF and
                                                             # the loop never ends

   This exact bug cost ~100 minutes of dead time on 2026-07-13: the jobs had
   finished and written their results, but two `pgrep -f` wait-loops were waiting
   on themselves, so nothing reported completion. Also: a completion callback can
   simply not arrive — check the ledger/log yourself before concluding a job is
   still running.

10. **An LLM-judge verdict is a hypothesis — verify it against the artifacts
    before acting.** The 101_003 triage judge proposed adding an *exclusive*
    window-boundary sentence; the prompt's own line 31 and the gold both state
    the *inclusive* rule, and the candidate had implemented it byte-identically
    to the gold. Applying the judge's sentence would have made the prompt
    contradict its task. The REAL gap (an undocumented `keys/1` the harness
    asserts) was found by grading the failed candidate and reading the failure
    list. Judge rows in `screen_triage.jsonl` need a human cross-check against
    prompt + gold + candidate before any prompt edit; record overrides as
    appended rows (last row per (task, sha) wins).

11. **A heuristic classifier's "observable" is a hint, not a measurement.**
    `classify_survivors` called 077_001's 15 AVL-bookkeeping survivors
    observable because its vocabulary didn't know tree internals — this file
    then called the family "the hardest real gap". Public-API fuzzing proved
    every survivor behaviorally identical to the reference. Before spending
    calls (or hand effort) on a below-floor family, fuzz its survivors through
    the public API; extend the classifier's vocabulary when it misfires.

12. **`kill -0` on run_detached's echoed pid can false-negative while the job
    LIVES ON.** The echoed pid is the wrapper; the beam it launched can outlive
    it. On 2026-07-15 a rubric batch read as "exited" mid-root, was relaunched,
    and two instances ran side by side writing duplicate ledger rows (benign —
    rows are append-only and consumers take the last per task — but noisy, and
    with a non-idempotent tool it would have been corruption). Before declaring
    a detached job dead: check the LOG is no longer growing AND `pgrep -af` for
    its actual command (one-shot, not in a wait loop — rule 9 above). Ledgered
    tools that must never self-overlap now take a `/proc`-checked lock file
    (rubric_judge's `acquire_lock!` is the pattern).

13. **Never edit `lib/` or `scripts/` while a ledgered mix-run tool is in
    flight.** Those tools spawn NESTED `mix run` subprocesses (resync
    cascades, evals) that recompile the project mid-run; an in-progress edit
    turns that recompile into a failure inside the tool's apply step
    (2026-07-15: a fully-gated 037_003 close ended `reverted_tfim_resync_
    failed` because T1.8's lib edits landed mid-apply). The same class as
    rule 8's `git add -A` ban: don't mutate the factory while a factory
    process is alive. Docs and STATUS edits are safe.

14. **Every finding is a TWO-TIER work item (CONTEXT.md hard rule 7): fix the
    existing data AND gate the generation script so the class cannot recur.**
    A finding without its forward gate is not done — fixing existing data
    while generating the same defect again never converges on quality. The
    compliance table for open finding classes lives at the top of STATUS.md's
    quality register; the round-level version of this rule is docs/12 §7.3
    step 3 ("wire the new check into the loop + CI FIRST").

---

## 7. Runbooks

**Top up derivatives (free, CPU only)**

    mix run scripts/work_status.exs                 # what is owed
    GEN_ONLY=backfill scripts/run_detached.sh logs/topup.log mix run scripts/generate.exs
    # when it exits:
    elixir scripts/validate.exs --only "<touched globs>"
    elixir scripts/validate.exs --mutants --only "<touched globs>"
    elixir scripts/format_corpus.exs --check        # --apply if it deviates
    git add <explicit new dirs> && git commit && git push   # pre-push runs the gates

**Fix a weak family (the §5.3 recipe)**

    mix run scripts/classify_survivors.exs -- --only "013_001*"   # is it even work?
    mix run scripts/enrich_prompts.exs -- --go --only "013_001*"  # spec first
    mix run scripts/screen_blind_solve.exs --only "013_001*" --rescreen   # S6 ledger
    mix run scripts/strengthen_harnesses.exs -- --go              # then the harness
    # cascades + gates run inside the tools; verify with the four resync gates

**After ANY parent-prompt edit** (they all cascade):

    mix run scripts/resync_embeds.exs -- --wt-all --apply
    mix run scripts/resync_bugfix_embeds.exs -- --apply
    mix run scripts/screen_blind_solve.exs --only "<fam>*" --rescreen

**Verify a fresh bugfix mint**

    mix run scripts/audit_bugfix.exs $(ls -d tasks/bugfix_* | shuf -n 10 | sed 's|tasks/||')

---

## 8. What "done" looks like

Phase 3 (490 queued base ideas) may start once §5.1 items 1–3 are resolved. After
its first validated batch, **draw the line** (docs/12 §7.2): delete the catch-up
tooling (`resync_embeds.exs`, `rescreen_repaired.exs`, `strengthen_harnesses.exs`,
`enrich_prompts.exs`, `mint_repairs.exs` as a one-shot), delete the backfill
vocabulary, and flip `/STATUS.md` to **STEADY STATE** — one command produces new
data, every check lives inside the loop or CI, and nothing needs catching up.
