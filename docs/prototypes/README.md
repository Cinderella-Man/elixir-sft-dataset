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

## SUPERSEDED — production implementation lives in lib/eval_task/

As of branch `multifile-fim-eval`, the plan is **implemented**: the evaluator is now in
compiled, tested modules under `lib/eval_task/` (bundle, manifest, fim, phoenix_kit, analysis,
runner, discovery, cli, failure_collector), driven by the thin `scripts/eval_task.exs`, with
`scripts/run_all.exs` (3-shape discovery) and `scripts/validate.exs` (reference-green + FIM
mutation gate). These prototype scripts are kept only as design references. The 8 `solutions/`
were promoted into `tasks_multifile/*/solution.ex`. See `docs/03` §12 for the as-built log.
