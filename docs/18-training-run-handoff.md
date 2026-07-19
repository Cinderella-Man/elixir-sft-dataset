# 18 — Training-run handoff (fork arm (b), Kamil's both-arms directive 2026-07-19)

The export is training-ready. This doc is everything a training run needs to
consume it correctly and — just as important — the questions the run exists to
answer, so its results steer the next data work. The contract of record for
the export format is `docs/16`; this doc does not restate it, it points.

## 1. What to train on

- `results/export/train.jsonl` (14,051 examples) + `results/export/val.jsonl`
  (594 — 4 whole families: 032, 065, 073, 108). Regenerate any time with
  `mix run scripts/export_dataset.exs`; byte-reproducibility is CI-proven
  (`-- --check` round-trips every row from the corpus). The corpus state for
  the first run is tagged `export-v1-14645`.
- Every example is `messages` (standard chat turns) + `metadata`. Multi-turn
  only for `shape: "dialogue"`; everything else is one user + one assistant
  turn. Fence conventions and the FIM-as-chat decision: docs/16 §2.2.

## 2. Conventions the trainer must honor

- **Loss masking:** assistant turns only. For `dialogue`, final-turn-only loss
  is the recommended default — the intermediate assistant turns are
  real-but-rejected code; training on them WITH loss teaches the mistake
  (docs/16 §5b).
- **Split:** use the provided `metadata.split` — it is family-atomic and
  deterministic. Never re-split by example: ~92% within-family text overlap is
  BY CONSTRUCTION, and a random split makes val measure memorization.
- **Weights:** `metadata.sample_weight` is advisory (1.0 / 0.5 / 0.25) and
  encodes near-duplication (tfim/tdd/spec_fim at 0.25 share large context or
  whole completions with siblings). First run: honor it as a sampling weight.
  `metadata.family_size` supports per-family re-weighting instead — a knob for
  run #2 if shape-level weighting proves crude.
- **Difficulty metadata:** `difficulty_tier` (blind_solvable / keep_class /
  unscreened) is ledger-derived and advisory — useful for curriculum
  experiments, not required.

## 3. Eval protocol

- **Held-out val loss** per shape (the metadata makes per-shape slicing
  trivial) — cross-shape comparability is the point of one chat format.
- **Execution eval (the real one):** generate completions for val-family
  prompts and grade them with THIS repo's evaluator
  (`scripts/eval_task.exs <dir> <candidate-file>` — one JSON verdict per
  candidate; perfect = compiled, zero warnings, all tests green). The four
  val families cover single/fim/wt/tfim/bugfix/adapt/dedoc/sfim/tdd/specfim
  shapes. This is the metric that matters; val loss is the cheap proxy.
- **Baselines:** the same execution eval on the base model before fine-tuning.

## 4. The measurement questions (why this run exists)

Ranked; each converts a parked data-work question into a decision:

1. **Register monotony** — do generations parrot the corpus's dominant
   prompt registers? Measure completion diversity vs the base model.
   *Decides:* whether T2.6-proper (the ~2,700-prompt register rewrite, the
   most expensive parked item) is worth its LLM budget.
2. **Shape mix** — per-shape execution-eval deltas. Which shapes move the
   needle; do the 0.25-weighted shapes (tfim/tdd/spec_fim) help or drown?
   *Decides:* export weights for run #2, and whether any shape should grow
   or be capped in Phase 3 derivation.
3. **Difficulty curve** — performance split by `difficulty_tier`.
   *Decides:* whether keep-class tasks teach or confuse at this scale, and
   whether Phase 3 should bias its idea selection.
4. **Contamination sanity** — spot-check val-family generations for verbatim
   train-text reproduction beyond what family-atomicity predicts.

## 5. What NOT to do

- Do not train on `repair_*` content (already excluded from the export).
- Do not "fix" examples in the export — every gold is machine-verified at
  1.0; a suspected defect goes through STATUS/rule 7 against the CORPUS,
  and the export is regenerated.
- Do not mix another Elixir dataset into the first run — it would confound
  every measurement above.
