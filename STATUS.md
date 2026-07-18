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

### 🧑‍⚖️ WAITING ON KAMIL

**Optional follow-up C (low priority):** 009_003 balanced rewording
(candidate's caller-blocks emphasis needs a "server loop stays
responsive" counterweight), 007_002 guard sentences via strengthen path,
014_001/044_001 fresh editor retries (token-vet fired; needs a
ledger-row removal or tool change to re-run).

**Two stray repair dirs** minted in the audit's pre-restart first hour
(untracked, full triplets, no ledger row):
`tasks/repair_001_002_fixed_window_counter_01_audit_00/` and
`tasks/repair_001_003_hierarchical_limiter_01_audit_00/`. Evidence
07-17: mint_repairs counts both among its `exists` skips — same standing
flow, first two mints. Call: verify + commit like the other 68, or
delete + let the flow re-mint.

### 🔎 OPEN FINDINGS

**prompt_precision.exs tool gaps, measured by the full run (Task B — apply
before any future precision round):** (a) structural-vet failures discard
the proposal WITHOUT saving to `logs/prompt_precision_candidates/` —
unreviewable (hit 013_003/014_001/044_001); (b) the single-sample blind
gate false-rejected 8 of the 17 rejects (reds on tests the edit never
touched, mostly timing-sensitive) — consider one retry before discarding;
(c) keep-class roots (standing screen red, judge-kept) can NEVER pass the
blind-green gate, so precision improvements are unreachable there without
wiring in the strengthen path.

**Template-rule candidate (F22 Task B, for the Phase-3 template work):**
"for any input the prompt's own validation rules accept, the gold must
terminate promptly without crashing" — F22 is the proof; fold into the
T1.4 template rules alongside the LIFECYCLE RULE when next edited.

**15 audit compile-class needs_triage rows — RE-AUDIT IN PROGRESS
(Kamil's go 2026-07-18).** Root cause found: the 15 "compile:" rows were
the blind SOLVER's candidate failing to compile (truncated/malformed
replies) — zero evidence about the grown harness, mis-ledgered as a
verdict. Task B DONE: `retro_audit.exs` verify_and_write now retries a
non-compiling blind candidate once and ledgers a second failure under
its own distinct label (self-test green). Task A RUNNING: the 15 rows
removed from `logs/retro_audit.jsonl` (backup
`logs/retro_audit.jsonl.bak_20260718_compile_triage`) so the roots
re-open at the current gate; re-audit via
`scripts/retro_audit.exs --only "<names>"` detached — pilot 078_001
GREEN (harness grown 17→21, full gate stack + blind verify, WRITTEN;
reviewed in detail), remaining 14 RUNNING as pid 496168; log
`logs/retro_audit_compile15.log` (idempotent relaunch: same command —
ledger resumes).
Roots: 043_004, 061_003, 063_004, 071_001, 071_002, 071_003, 078_001,
100_001, 100_002, 100_003, 100_004, 104_004, 110_002, 110_003, 134_003.
AFTER: changed roots → cascade + commit; verdicts recorded in docs/15.
NOTE (new two-tier finding, Task B pending): retro_audit's row key
omits its own script bytes (gate_sha covers the four judged modules
only — prompt_precision.exs hashes its own file and is the right
pattern); fold the alignment in at the next deliberate ledger re-open,
NOT now (adding it now would silently re-open all 314 sound verdicts).

**Cutover-checklist fold-in still to land (docs/12 §5.5): repairs must
re-run the spec gate on the repaired file — F20 (a spec lie introduced
BY a repair) is the proof it's needed. Add the parity-table row when
docs/12 is next edited.**

### 🔨 BUILDS

**In-loop quarantine-triage path** (docs/17 §6.3): the loop can quarantine
but has no "hard-task KEEP" verdict (the retro screen had 49 keeps).
Phase 3 needs: triage judge over `logs/quarantine/*` + Kamil review + a
keep-promotion path writing the evidence row. Until built, quarantines
block their idea and surface here.

**T1.4 sliver (d)**: record each seed's blind-screen outcome as difficulty
metadata (ledger-side, tiny — fold into the export work).

### ⏭️ QUEUE ORDER

1. Next up: DATA EXTENSION below (TD.3 first — unblocked).

### 📦 DATA EXTENSION (docs/13 §2; after the above)

- **TD.3 — dedoc (~331 free units)** — NOW UNBLOCKED (T1.6 closed
  2026-07-17 with the pass reading clean-or-waived). §2.3.
- **T2.6 proper — prompt-register monotony rewrite** (improvement round
  #2 — NOT before steady state) [BIG: 2,396 tfim + 302 wt_ + 80/332 seed
  openers; own tool + ledger + blind re-screen budget] — docs/12 §7.4.
- **TD.2 — multi-turn repair-dialogue exporter** (PERISHABLE raw material —
  snapshot `logs/attempts/` before any big run; archives 2026-07-12 and
  2026-07-14b; 745 chains / 100 mintable rejected→accepted pairs). §2.2.
- **TD.4 — style-repair pairs (207) + cap lifts (~1,900 free tfim)** —
  weigh against docs/16 §4's advisory weights. §2.4–2.5.

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
