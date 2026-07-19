# PROJECT STATUS — the live work list (read after CONTEXT.md's HOW-WE-WORK rules)

**HARD RULE (CONTEXT.md rule 5): this file contains ONLY todo / in-progress /
blocked items — NOTHING that is done.** Completed work moves immediately to
`docs/15-completed-work-log.md` (and lives in git history). Update it AS YOU
GO — before launching a job, after finishing one — never "at the end".

Reference docs: `docs/14` (handover: gates, tools, ledgers, runbooks),
`docs/12` (quality standard; §7 = the two modes + round protocol),
`docs/16` (export contract), `docs/18` (training-run handoff),
`docs/15` (everything finished).

---

## Current mode: ✅ STEADY STATE (line drawn 2026-07-19, docs/12 §7.2)

The catch-up campaign is FINISHED. Every task that exists passed Standard v1;
every check lives in the generation loop or CI; one command produces new data
with all eleven derived shapes and no post-processing:

    mix run scripts/generate.exs

The corpus: **14,645 exported examples (~56M tokens, 12 shapes, 83
families)** — tag `export-v1-14645`, all sweeps green (perfect + fim +
mutants + decontam), export round-trip proven. Raising the standard ever
again follows the six-step improvement-round protocol (docs/12 §7.3):
flip this file to CATCHING UP first, wire the new gate into the loop + CI
BEFORE touching data.

---

## 📋 TODO

**1. Phase 3 — new-base generation (Kamil's go, not before).** 490 queued
ideas. THE FIRST BATCH OWES THE CUTOVER ACCEPTANCE TEST (docs/12 §5.5
bottom, reaffirmed at the line): run ~20 bases
(`scripts/run_detached.sh logs/phase3_batch1.log env GEN_LIMIT=20 mix run
scripts/generate.exs`), then BEFORE the throttle opens: full
`semantic_review` of every new root + a `rubric_judge` two-family pass +
perfect/mutant/embed/format sweeps + export round-trip — ZERO triage-grade
findings, else fix the GENERATOR (never the data), regenerate, re-test.

**2. Training run (fork arm (b), Kamil's infra).** Everything needed is in
`docs/18` + `results/export/` at tag `export-v1-14645`. Its measurements
(register monotony, shape mix, difficulty curve) decide the next data work
— including whether T2.6-proper's register rewrite is worth its budget.

**Parked (unchanged):** T2.6-proper (round #2 per the 07-16 sign-off);
keep-packet approvals (Kamil, any time).
