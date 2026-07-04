# Multifile-support prototypes (validated, reference only — NOT production)

These are the throwaway scripts that proved feasibility during the design of
`docs/01-multifile-task-support.md`. They run against the repo's compiled deps.

- `eval_multifile.exs` — integrated prototype of the proposed evaluator: parses a
  `<file>` bundle, **infers the archetype + prefix from the harness**, routes to a
  Tier-A (compile+run) or Tier-B (Phoenix+SQLite host kit) path, and prints a JSON
  result. Run: `mix run docs/prototypes/eval_multifile.exs <task_dir> [solution_file]`.
  Verified green: 102 (pure_otp) 18/18, 016 (phoenix_conncase) 14/14, and 021 (plug,
  against a bug-fixed harness) 20/20.
- `sol_021_versioned_api.ex` — a minimal `<file>`-bundle solution for the unsolved
  task 021, used to prove the `plug_selfcontained` archetype. Passes 20/20 once 021's
  harness dead-code bug is removed (see task T4 / T-021-FIX in docs/02).

The production versions of this logic belong inside `scripts/eval_task.exs` +
`test/support/kits/` per the task breakdown in `docs/02-multifile-task-breakdown.md`.

## FIM (fill-in-the-middle) prototypes

- `eval_fim.exs` — reconstruct a full module from a FIM task's `prompt.md` skeleton + a
  candidate function (spliced at the `# TODO` marker), then run the PARENT (`_01`) task's
  harness. Run: `mix run docs/prototypes/eval_fim.exs <fim_dir> [candidate_file]`.
  **Verified: 54/54 FIM reference solutions reconstruct + pass their parent harness.**
  Handles both splice conventions (stub-body `def … do # TODO end` and placeholder-line
  `#TODO defp foo`). Discriminates: a wrong body fails the harness; bad syntax won't compile.
- `mut_fim.exs` — the mutation check for the validator: replaces the target's body(ies) with
  `raise` and asserts the parent harness now FAILS (proving the target is exercised).
  **Verified: 54/54 GOOD_exercised — no existing FIM is under-tested.**
  Run: `mix run docs/prototypes/mut_fim.exs <fim_dir>`.

## Unified evaluator + validated solutions (design review 3)

- `eval_task_v2.exs` — the UNIFIED 3-shape evaluator prototype: detects single-file / multi-file
  / FIM, routes multi-file to Tier-A (compile) or Tier-B (Phoenix+SQLite host kit) by inferred
  archetype, reconstructs FIM, and scores with shape-appropriate rubrics. **Single-file scoring is
  byte-identical to the current `scripts/eval_task.exs`** (backward-compat verified). Run:
  `mix run docs/prototypes/eval_task_v2.exs <task_dir> [solution_file]`.
- `solutions/` — 8 validated `<file>`-bundle solutions proven green through the evaluator:
  017/018 normalized to domain-only, and the 6 previously-unsolved self-contained tasks
  (020, 021, 022, 023, 024, 025). These become the actual task solutions (docs/02 T4/T6).

NOTE: `eval_task_v2.exs` reproduces the current (buggy) analysis-scoring for backward-compat; the
production fix (award by pass/fail, drop Credo) is task T-SCORE-FIX (docs/02 §G, docs/03 §3.1).

## Dataset-multiplication prototypes (docs/07, verified 2026-07-03)

Feasibility proofs for the roadmap in `docs/07-dataset-audit-and-growth-roadmap.md` §11.
All run from the repo root with `mix run docs/prototypes/<name>.exs`.

- `proto_mutant_repair.exs` — §4.3 mutant-repair minting: mutates one public function of
  002_001 via `GenTask.Mutation.mutate_fn`, grades the mutant (14/15 fail, failures
  captured), assembles a repair `prompt.md`, and re-grades the gold (15/15, 1.0).
  **VIABLE**; caveat: raise-mutant failure messages are uniform ("MUTATION") — production
  wants subtler operators for realistic repair prompts.
- `proto_dedoc.exs` — §4.4 de-documentation pairs: heredoc-aware strip of
  `@moduledoc`/`@doc`/`@spec`, verified green on 3 tasks with overall dropping
  1.0 → 0.85–0.87 (the docs are the training delta). **VIABLE**, self-filtering via grading.
- `proto_det_sfim.exs` — §4.6 deterministic code-FIM: carves multi-clause `handle_call/3`
  from 002_001 without any LLM, builds a FIM dir, and the real evaluator reconstructs +
  passes 15/15. **VIABLE**; production must blank all clauses into a single stub (this
  prototype leaves one stub per clause, which the splice leaves dangling).
- `proto_tfim_yield.exs` — §4.1 yield measurement with the production carver
  (`GenTask.TestFim.test_blocks/1`): 3,003 carvable blocks over 204 harnesses (median 14),
  cap-3 predicts 582 vs 579 actual; cap 10 → 1,897; cap 15 → 2,514 (upper bounds before
  the isolation-kill gate).
- `proto_vacuous_green.exs` — demonstrates docs/07 §6.1 #1: an all-`@tag :skip` harness
  with FALSE assertions grades `passed=2, overall=1.0` and `GenTask.Evaluator.green?/1`
  returns true — skipped tests are counted as *passed* (`runner.ex` never subtracts
  ExUnit's `skipped` count). **FIXED 2026-07-03 (docs/08)** — re-running it now prints
  `passed=0, overall=0.3, green?=false / not reproduced`.
- `proto_attempt_capture.exs` — end-to-end demo of attempt capture (docs/08 §4): drives
  `GenTask.Cycle.run` through a green ACCEPT (quality + per-fn mutation gates) and a
  raise-mutant REJECT with `logs_dir` in a tmp dir, then prints the captured
  `logs/attempts/<id>/attempt_NN/{files/,grade.json,meta.json}` tree and verifies
  reset-on-rerun semantics.

## SUPERSEDED — production implementation lives in lib/eval_task/

As of branch `multifile-fim-eval`, the plan is **implemented**: the evaluator is now in
compiled, tested modules under `lib/eval_task/` (bundle, manifest, fim, phoenix_kit, analysis,
runner, discovery, cli, failure_collector), driven by the thin `scripts/eval_task.exs`, with
`scripts/run_all.exs` (3-shape discovery) and `scripts/validate.exs` (reference-green + FIM
mutation gate). These prototype scripts are kept only as design references. The 8 `solutions/`
were promoted into `tasks_multifile/*/solution.ex`. See `docs/03` §12 for the as-built log.
