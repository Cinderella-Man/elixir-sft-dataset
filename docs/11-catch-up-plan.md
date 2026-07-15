# 11 — Catch-up plan: finish quality assurance first, then backfill, then new tasks

Date: 2026-07-10. Agreed with Kamil. This doc is deliberately written in plain
language — see the glossary at the bottom for the project's shorthand terms.

> **Current status always lives in [`/STATUS.md`](../STATUS.md).** The concrete
> work list inside these phases, the quality standard, and the exit protocol
> live in `docs/12-quality-standard-and-steady-state.md`.

## The plan, in one paragraph

We stop generating new content until the quality-assurance work on the
**existing** corpus is finished. Order: (1) fix the two known open QA items —
the stale prompt copies and the broken seed self-check — plus any smaller
leftovers below; (2) when the existing corpus is fully clean and nothing else
is left, run one **backfill** pass to top up derivatives for tasks that
already exist; (3) only after backfill is complete, start generating the 490
queued **new** base tasks. Generation runs always go through
`scripts/run_detached.sh` and the model is hardcoded to Opus in
`scripts/generate.exs`.

## Phase 1 — quality-assurance catch-up (current phase)

### 1a. The 632 stale prompt copies ("stale tfim embeds") — ✅ DONE 2026-07-10

Plain-language explanation of the problem: every *tfim* exercise is a child
of a parent task. The child's `prompt.md` contains a full **copy** of the
parent's code and test file, with one test blanked out for the trainee model
to write. Over the past months we edited many parent files (bug fixes,
warning fixes, renames) but never refreshed the copies pasted inside child
prompts. Result: **632 child prompts (across ~77 families) show an outdated
copy of the parent code**. No gate notices, because grading always runs
against the parent's real files — the copy is display text only. But the
copy is exactly what the trained model *sees*, so it must match reality.

The fix is mechanical and costs zero LLM tokens:
1. `mix run scripts/resync_tfim_embeds.exs -- --apply` — deterministically
   regenerates every child prompt from the current parent files.
2. Full-corpus validation + `mix format --check-formatted`.
3. Commit as one mechanical commit.
4. Add the script's dry-run (`errors: 0, would_resync: 0`) to CI and the
   pre-push hook, so prompts can never silently drift from their parents
   again.

### 1b. Fix the seed self-check that wrongly blocks 5 families (50 tfim units) — ✅ DONE 2026-07-10

Before deriving child exercises from a parent, a self-check verifies the
parent's test suite actually tests something (it breaks the parent's code on
purpose and expects the tests to fail). Bug: the check stages the broken
copy **without the parent's `manifest.exs` file**, so parents that need it
(the Phoenix/Ecto "tier B" tasks) fail to compile and the check reports
"inconclusive" — and derivation is skipped as if the tests were worthless.
`work_status.exs` currently shows 5 blocked families: 018_001, 019_001,
074_001, 074_002, 074_004 (the 074s are macro modules — likely the related
compile-time-error case; verify while fixing).

Fix: copy `manifest.exs` into the staging directory the same way
`grade_harness_against_module/3` already does; count a compile error caused
by the mutation as a valid "tests would catch it" outcome (the `--mutants`
sweep already does this). Then **delete the affected cached verdicts from
`logs/seed_verdicts.jsonl`** — the cache key is the test-file content, which
did not change, so without deleting, the wrong verdicts stick forever.

### 1c. Smaller open QA items

- **Flaky-test watch (R9)**: keep aggregating `logs/flaky.jsonl` across days
  (`jq -r .task logs/flaky.jsonl | sort | uniq -c`); quarantine any task that
  appears repeatedly. Two repeat offenders already fixed (104_004, 625_001).
- **Prompt-wording monotony (docs/07 §4.2 / §5.1)**: 2,318 tfim prompts open
  with the identical phrase. A rewrite pass costs LLM tokens — decide scope
  before backfill or fold into a later improvement round.
- **Random spot-review (docs/10 §4.4)**: a stratified sample of accepted
  tasks reviewed by a human/LLM judge for "does this make sense" — the one
  check class no automated gate covers. Decide whether it blocks Phase 2 or
  runs in parallel.

## Phase 2 — backfill (only when Phase 1 is done)

Top up derivatives for existing tasks: currently 11 variation expansions,
25 FIM seeds, 103 tfim seeds (~624 units, including the 50 unblocked by 1b).
Run: `GEN_ONLY=backfill scripts/run_detached.sh logs/backfill.log mix run
scripts/generate.exs` — backfill only, NOT the mixed everything-run.
Idempotent; safe to re-run after any interruption.

## Phase 3 — new generation (only when Phase 2 is done)

The 490 queued base ideas in `tasks/tasks.md` (135_001 onward), via the same
detached runner. This is where new dataset content starts again.

## Glossary (project shorthand, plainly)

- **base task / `_01`**: an original exercise — prompt + reference solution +
  test file — authored from one catalog idea.
- **variation / `_02`..`_04`**: a sibling exercise derived from the same idea
  with meaningfully different requirements.
- **FIM ("fill in the middle")**: a child exercise showing the solution with
  one function removed; the trainee model writes the missing function.
- **tfim ("test fill in the middle")**: same idea but for tests — the child
  shows the full test file with one test blanked to `# TODO`.
- **`wt_` ("write test")**: a child exercise asking the model to write a whole
  test suite for a given solution.
- **embed**: the copy of parent code/tests pasted inside a child's prompt.
- **resync**: regenerating those copies from the current parent files.
- **harness**: the test file (`test_harness.exs`) that grades a solution.
- **mutant / mutation gate**: we deliberately break a solution and require the
  tests to fail; if they still pass, the tests are worthless ("vacuous").
- **screen / blind solve**: an independent model solves a task from the prompt
  alone; failure flags prompts that omit necessary information.
- **quarantine**: a task flagged red by the screen, excluded until triaged.
- **seed**: an accepted base/variation task that derivatives are built from.
- **backfill**: generating missing derivatives for existing seeds (no new
  ideas).
- **root**: a base or variation task — the tasks all child exercises (FIM,
  tfim, wt_, bugfix, adapt) are derived from. A defect in a root is copied
  into every child, so root-level checks matter most.
- **built dark / dark flag**: a quality check that is fully built, tested,
  and wired into the generation loop but SWITCHED OFF by default via an
  environment variable (e.g. `GEN_PROMISE_AUDIT=1`,
  `GEN_BLIND_RESCREEN=1`, `GEN_SEMANTIC_FLOOR=0.6`). With the switch off the
  loop behaves exactly as before, except the run log prints a
  `SKIPPED — … DARK` line so the inactive check stays visible. New checks
  land this way so they can be piloted first and only start affecting
  accept/reject decisions on Kamil's explicit go.
- **flipping a flag**: turning such a switch on permanently (usually by
  adding the variable to the standard run command).
- **promise audit** (`GEN_PROMISE_AUDIT`): the accept-time check that reads
  the prompt as a list of promises, has a reviewer model write a test for
  each promise no existing test covers, and machine-verifies every proposed
  test before it counts (see "bite-proven" and "evidence-or-drop").
- **bite-proven**: a newly added test only ships if it demonstrably "bites" —
  it must FAIL when the behavior it claims to pin is deliberately broken
  (and pass against the correct solution). A test that cannot fail proves
  nothing and is dropped.
- **evidence-or-drop**: the rule that a reviewer model's claim ("this code
  violates the prompt") only counts if it comes with a test that actually
  fails against the current solution; a claim whose test passes is treated
  as a hallucination and silently dropped.
- **probe / probe-proven**: a small throwaway script or test written to
  demonstrate a suspected bug on the real code before acting on it; a
  finding is "probe-proven" once that demonstration failed/succeeded as
  predicted.
