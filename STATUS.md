# PROJECT STATUS — the live work list (read after CONTEXT.md's HOW-WE-WORK rules)

**HARD RULE (CONTEXT.md rule 5): this file contains ONLY todo / in-progress /
blocked items — NOTHING that is done.** Completed work moves immediately to
`docs/15-completed-work-log.md` (and lives in git history). Update it AS YOU
GO — before launching a job, after finishing one — never "at the end".

Reference docs: `docs/14` (handover: gates, tools, ledgers, runbooks),
`docs/12` (quality standard; §7 = the two modes + round protocol),
`docs/13` (data-extension designs), `docs/15` (everything finished).

---

## 📋 TODO (rules 7–10 apply: every finding = Task A fix data + Task B gate
the generator; pilots before full runs; one solved item = one commit)

### Everything derivable from the existing corpus is DONE (2026-07-19,
### docs/15: 14,645 examples / 12 shapes / all sweeps green / every
### shape reproducible by one generation run). What remains below is
### Kamil's strategic call plus its downstream chain.

**THE FORK — RESOLVED BOTH-ARMS-IN-PARALLEL (Kamil 2026-07-19 ~13:30:
"do whatever you've recommended in parallel if possible", endorsing the
recommendation that the arms are not mutually exclusive). That directive
also constitutes the LOOP-PARITY WAIVER for rows 11/17/21 (their
explicit post-cutover instruments stand in for the literal ENFORCED) —
authorizing Phase 3 implies accepting the table's state; recorded in
docs/12 §5.5.**

**(a) PHASE 3 PILOT BATCH — IN FLIGHT:** GEN_LIMIT=20 new bases through
the full loop (each accepted root auto-derives all eleven shapes via
the Work registry). Detached: logs/phase3_pilot.log; idempotent
relaunch: `scripts/run_detached.sh logs/phase3_pilot.log env
GEN_LIMIT=20 mix run scripts/generate.exs`. LLM run — rides token
windows; expect hours. ON EXIT, BEFORE the throttle opens, the CUTOVER
ACCEPTANCE TEST (docs/12 §5.5 bottom) is MANDATORY: full
semantic_review of every new root + a rubric_judge two-family pass +
perfect/mutant/embed/format sweeps + export round-trip — ZERO
triage-grade findings, else fix the GENERATOR (never the data),
regenerate, re-test.

**(b) TRAINING-CYCLE HANDOFF — being prepared in parallel:** the export
is training-ready (14,645 examples, round-trip-proven reproducible);
writing docs/18 (training-run handoff: serialization, loss-masking,
weights/split usage, the measurement questions the run must answer) and
tagging the export state. The actual training run happens on Kamil's
training infra — the handoff is the parallelizable half.

Still parked: T2.6-proper (round #2 per the 07-16 sign-off);
keep-packet approvals (Kamil, any time).

---

## Current mode: 🔧 CATCHING UP (improvement round #1, 2026-07)

New base generation is **paused**. Mode definitions + round protocol:
docs/12 §7; round history + everything finished: docs/15. Remaining exit
conditions:

- [ ] **LOOP PARITY (docs/12 §5.5)**: every row of the parity table reads
      ENFORCED or is explicitly waived by Kamil.
- [ ] Phase 3: new generation resumed (490 queued bases) and the first
      batch passes the **cutover acceptance test** (docs/12 §5.5 bottom):
      full semantic_review of every new root + a rubric_judge two-family
      pass + all sweeps — ZERO triage-grade findings, else stop and fix
      the GENERATOR, never the data.
- [ ] The line drawn (docs/12 §7.2): delete catch-up tooling per the §7.2
      + docs/14 disposition tables (the four resync DRIFT GATES and the
      standing audits stay), remove the backfill vocabulary, delete the
      `../elixir-sft-dataset-t16` worktree, flip this file to STEADY STATE.
