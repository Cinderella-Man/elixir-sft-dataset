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

**T2.6 post-triage follow-ups (2026-07-18; the 17-root triage record is in
docs/15).** Two small prompt-writing LLM batches — same write gate as the
full run (land only on blind green, revert on red; never concurrent with
the nightly sweep or another prompt-writing tool), so Kamil's go first:

- **Follow-up A — RERUN the 8 false rejects (~8 blind solves).** Per root:
  apply the saved candidate from `logs/prompt_precision_candidates/<id>.md`,
  run ONE blind solve (hand-pilot flow); green → keep + S6 row + cascade;
  red → revert (the reverted sha's needs_triage ledger row still stands).
  Roots: 012_001, 024_002, 025_001, 025_003, 045_001, 064_004, 073_001,
  624_002. Triage evidence: every candidate addition verified
  harness-pinned; every red hit a test the edit never touched (5 of the 8
  are timing/choreography-sensitive tests).
- **Follow-up B — HAND-FIX the 3 real precision gaps (~3 edits + blind
  solves).** 007_001: state the gold's ACTUAL trim rule (trim only on a
  non-growing `get`; a growing `get` reads the untrimmed buffer — the
  rejected candidate stated it backward). 041_003: state the
  raise-vs-error-tuple split (missing `:name` → KeyError raises in the
  caller; missing `:num_shards`/`:max_size` → `{:error, {%KeyError{}, _}}`
  from start_link, fetch in init). 072_004 (HIGH VALUE): apply its saved
  candidate (names the pinned start-validation error tuples — the exact
  cause of this root's STANDING screen red) + one sentence pinning the
  CALLER-side RuntimeError re-raise in `now/1`. 007_001/072_004 are
  keep-class → strengthen path if still red after the fix.
- Optional low-priority C: 009_003 balanced rewording (candidate's
  caller-blocks emphasis needs a "server loop stays responsive"
  counterweight), 007_002 guard sentences via strengthen path,
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

**~15 audit needs_triage rows are staging COMPILE errors** (the grown
harness never compiled, so no blind screen row exists and the 07-17
judge sweep could not cover them; the roots on disk are unaffected and
green). List:
`jq -r 'select(.outcome=="needs_triage") | select(.detail|contains("compile:")) | .task' logs/retro_audit.jsonl`
Triage: re-run the promise audit on these roots (`generate.exs <n>`
paths) or log them as auditor-bug evidence — rule 7 either way.

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

1. **T2.6 post-triage follow-ups A + B** — WAITING ON KAMIL (see above).

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
