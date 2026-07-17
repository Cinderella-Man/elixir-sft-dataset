# PROJECT STATUS — the live work list (read after CONTEXT.md's HOW-WE-WORK rules)

**HARD RULE (CONTEXT.md rule 5): this file contains ONLY todo / in-progress /
blocked items — NOTHING that is done.** Completed work moves immediately to
`docs/15-completed-work-log.md` (and lives in git history). Update it AS YOU
GO — before launching a job, after finishing one — never "at the end".

Reference docs: `docs/14` (handover: gates, tools, ledgers, runbooks),
`docs/12` (quality standard; §7 = the two modes + round protocol),
`docs/13` (data-extension designs), `docs/15` (everything finished).

---

## ▶️ RUNNING RIGHT NOW

**Push of the tranche close-out (detached, log
`logs/push_v8_20260717.log`).** The §4.2.2 spot-review tranche is
COMPLETE — 20/20, 15 ok / 5 findings, full record in docs/15 and
`logs/spot_review.jsonl`. F22 remains the one OPEN code-defect finding
(item below); the four prompt-precision findings (002_001, 003_001,
009_001 minor, 034_001 minor) plus the uniformity nits join the T2.6
material. Next queue item: the T2.6 prompt-precision tool — but its
scope now has three inputs waiting on Kamil (the 19-root sign-off
queue, the tranche's prompt findings, and the improvement-round-#2
boundary docs/12 §7.4), so the tool build should start AFTER Kamil's
sign-off pass. Tranche
list `logs/spot_review_tranche_20260717.txt` (20 seeds, deterministic:
April-era ∩ audit-changed-harness-only ∩ 0 proven-defect promise tests
— the machinery's blind spot — one per idea family, 58-candidate pool).
Verdicts append sha-keyed to `logs/spot_review.jsonl` (task, file shas,
verdict ok|finding, notes) — resume = skip rows whose shas match.
Method: fresh-eyes read of prompt + solution + harness targeting
MEANING (gold bugs, contract mismatches, harness blind spots); rule 7
on every finding. Precedent rate: ~2 defects per 12 roots (the 07-13
tranche) and 1 gold bug per 4 roots (the 07-15 T2.6 pilot).
(Pushed through e9681997: T1.11 + T1.6 arcs fully closed on origin.)

---

## 📋 TODO (rules 7–10 apply: every finding = Task A fix data + Task B gate
the generator; pilots before full runs; one solved item = one commit)

### 🧑‍⚖️ WAITING ON KAMIL

**1. Prompt-gap sign-off queue — 19 roots from the 07-17 judge sweep
(prompt edits are never automatic; each applied edit cascades: sha-keyed
re-screen + embed resyncs, docs/10 invariant #5).**
`mix run scripts/triage_screen.exs -- --report` prints every root with
its proposed one-sentence fix (ledger `logs/screen_triage.jsonl`).
Review notes: (a) split the list by origin — roots also in
`logs/rescreen_pending.txt` are re-screen reds whose NOT-entailed
assertion lives in the SHIPPED harness (prompt↔harness inconsistency:
fix prompt OR harness, higher priority), while audit-red roots' grown
tests were already discarded (sentence = optional T2.6 improvement);
(b) 031_001's 07-17 row has a sound not-entailed reason but a NULL
proposed sentence (incomplete judge reply) — write it by hand;
(c) some proposals read like implementation over-specification (e.g.
037_002's verbatim word lists, 079_002's exact defstruct) — rejecting
the grown test is a valid outcome there. The 83 keeps need no action
(evidence rows recorded; they feed the quarantine-keep design and T2.6
scoping). **(d) ADDED by the §4.2.2 spot-review (see
`logs/spot_review.jsonl`): 002_001 — three prompt-precision defects
incl. an unobservable-by-construction :half_open contract and a
vestigial half_open_max_probes option (details in the ledger row);
Task-B candidate template rule: "no documented option or state may be
unobservable".**

**2. Two stray repair dirs** minted in the audit's pre-restart first hour
(untracked, full triplets, no ledger row):
`tasks/repair_001_002_fixed_window_counter_01_audit_00/` and
`tasks/repair_001_003_hierarchical_limiter_01_audit_00/`. Evidence
07-17: mint_repairs counts both among its `exists` skips — same standing
flow, first two mints. Call: verify + commit like the other 68, or
delete + let the flow re-mint.

### 🔎 OPEN FINDINGS

**F22 — 004_001 scheduler crash on unsatisfiable-but-valid cron
(§4.2.2 spot-review, 2026-07-17).** `0 0 31 4 *` (April 31; also Feb
30/31) passes field validation, then the next-run scan walks to its
2.2M-iteration cap (~seconds of CPU) and RAISES inside `handle_call` —
crashing the scheduler and losing every registered job. Harness has
zero impossible-date coverage; invisible to all standing gates. Task A
(Kamil direction needed — behavior change, full cascade): reject at
registration (`{:error, :invalid_cron}` for never-matching
expressions) or document the limitation + bound the scan gracefully.
Task B: template/lint rule candidate — "for any input the prompt's own
validation rules accept, the gold must terminate without crashing";
check the other scheduler-family roots (004_002/3/4) for the same
class when fixing. Full row in `logs/spot_review.jsonl`.

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

1. **§4.2.2 spot-review tranche**: ~20 April-era seeds stratified against
   the sweep ledger toward audit-clean roots (doubles as the T2.2 residue
   check; signed off 2026-07-16).
2. **T2.6 prompt-precision tool** (same skeleton as retro_audit.exs; feed
   it the judge-sweep verdicts in `logs/screen_triage.jsonl`) — never
   concurrently with the sweep.

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
