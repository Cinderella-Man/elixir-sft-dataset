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

### ▶️ DAY SESSION 2026-07-19 (Kamil, ~09:30: "finish everything besides
### new task generation"; two directed decisions: 110_002 APPROVE, and
### UNPARK all three derivation builds — spec-fim, TDD-inverse,
### bundle-v2; T2.6-proper stays round #2 per the 07-16 sign-off).
### Work queue (items 1-4 + the CI red DONE — docs/15 morning entry;
### build order corrected by integration-cost investigation):
### 4h WINDOW CLOSED (docs/15): items 5-9 all done — tdd + spec-fim +
### bundle-fim shipped, loop derivation completeness proven by the
### loop's own backfill (work matrix fully green), F26 caught by the
### push gate and buried two-tier, and the FULL close-out sweep is
### green: ALL PERFECT (~14.6k dirs) + ALL FIM TARGETS + ALL MUTANTS
### KILLED + decontam 0 flagged. Export: 14,645 examples (~56M tokens),
### round-trip OK.

**Standing decision (Kamil):** the strategic fork — Phase 3 (490 queued
bases; ~57/1000 ideas realized is the binding constraint) vs a
training/eval cycle on the export (converts the parked questions —
register monotony, shape weights, difficulty curve, T2.6-proper's worth
— into measurements).

**Phase E — the honest fork (Kamil; roadmap Phases A–D all done, see
docs/15):** after C, existing-corpus
derivation is ESSENTIALLY EXHAUSTED. Remaining upside: (a) Phase 3 —
base-idea diversity (57 of ~1000 ideas realized) is the binding
constraint no derivation fixes; or (b) run a training/eval cycle on the
export and let its results (register monotony? shape mix? difficulty
curve?) decide the next data work — incl. whether T2.6-proper's big
register rewrite is worth its LLM budget. PARKED until then:
T2.6-proper, spec-fim (1,869 sites), TDD-inverse, bundle-v2 coverage
(6 dirs), keep-packet approvals (Kamil, any time).

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
