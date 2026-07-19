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

**THE FORK (Kamil — the only live decision):** (a) **Phase 3** — resume
new-base generation (490 queued ideas; base-idea diversity at ~57/1000
is the binding constraint no derivation fixes), or (b) **a
training/eval cycle on the export** — converts the parked questions
(register monotony, shape weights, difficulty curve, whether
T2.6-proper's big register rewrite is worth its LLM budget) into
measurements before more data work. Still parked pending the fork:
T2.6-proper (round #2 per the 07-16 sign-off) and keep-packet approvals
(Kamil, any time).

**LOOP-PARITY SIGN-OFF (Kamil, small):** row 16 closed 2026-07-19 (the
table's last MISSING row). Rows 11/17/21 carry explicit post-cutover
instruments rather than the literal word ENFORCED — say whether that
framing counts as your waiver, and the parity exit condition below
checks off.

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
