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

### ▶️ NEXT SESSION RUNBOOK (written 2026-07-19 at context limit —
### follow IN ORDER; each step says exactly what and why)

**OVERNIGHT SESSION 2026-07-19 (running now).** MONITOR PROTOCOL (Kamil
01:10): a 15-min heartbeat background monitor is ALWAYS armed — fires on
job exit OR every 15 min, re-armed on every wake; if the 5h token window
exhausts, the queued heartbeat re-invokes the session the moment it
refreshes (detached scripts ride outages on their own). Successor
sessions: keep this cadence all night. Order tonight: STEP 2 keep_land
(in flight) → Phase D decontam re-run → STEP 3 refresh (will include the
182 dialog_ units — Phase B turned out FULLY BUILT: miner + dirs +
exporter :dialogue arm + round-trip all exist; roadmap section below is
stale on this) → STEP 4 wire the spec-embed gate
(scripts/resync_sfim_specs.exs is WRITTEN + parse-checked; self-test +
corpus dry-run + pre-push/CI wiring + commit remain). STEPs 0-1 are
DONE + PUSHED (0844ab13..b047b676, all pre-push gates green): Phase C
shipped at 2,530 units through the F24 carver finding — full story in
docs/15 (2026-07-19 night entry).

**Open notes for Kamil (non-blocking, from the F24 landing):**
(a) template-parenthetical harmonization — the sfim prompt's "including
the @doc/@spec lines shown above it, if any" is mildly stale for
doc-carved units (docs live in the GOLD now, absent from the skeleton;
docless answers still grade 1.0; the gold's shape teaches house-style
documenting, which is what we want) — harmonize via the new
resync_sfim_specs gate in one deterministic pass if desired;
(b) optional --self-test T-gate alignment for the validate-side F24
check (bite machine-proven: fired on 1,084 real units + 4 honest
rejects).

**STEP 2 — DONE 02:15: all four follow-up C landings shipped (3 green
first blind solves + the 007_002 directed keep), six-gate cascade + one
commit each (f1777c18, d80329e9, 8f09a509, 6f4c80d6) — docs/15 entry
written. Next: Phase D decontam re-run, then STEP 3.**

**STEP 3 — DONE 02:20 except the push: decontam re-run CLEAN (0/25,112
corpus texts flagged), export refreshed 12,466 examples (11,988/478
family-atomic, round-trip OK), README at-a-glance updated (fim 3,532,
~51M tokens, conservative count 5,964). Final push IN FLIGHT:
logs/push_step3.log — carries STEPs 2-4 commits; the new sfim-spec
pre-push block executes for the first time in it.**

**STEP 4 — DONE except push-verification: the sixth drift gate
(scripts/resync_sfim_specs.exs) is BUILT, self-tested (5/5, plants a
PARENT edit), report-only like its siblings, wired into .githooks/
pre-push + CI validate.yml, and PROVEN LIVE on its first real drift:
the 009_003 keep_land landing staled that family's 7 sfim children and
the gate flagged exactly those 7 (2,534 unchanged). It heals them in
the 009_003 cascade. Rides the next push; its pre-push block executes
for the first time then.**

**Standing decisions (Kamil, unchanged):** 110_002 keep packet
(--approve or delete; then retro_audit --only "110_002*" so its staged
growth lands); the strategic fork — Phase 3 (490 queued bases; ~57/1000
ideas realized is the binding constraint) vs a training/eval cycle on
the export (converts the parked questions — register monotony, shape
weights, difficulty curve, T2.6-proper's worth — into measurements).

### ⏭️ ROADMAP (established 2026-07-19 night; Kamil's frame: improve +
### derive from existing, no new-task generation)

**Phases A–D: ALL DONE (docs/15).** A (tfim cap-lift + rubric pass #2)
finished earlier on 2026-07-19/20; B (dialog_) turned out fully built —
182 dirs + exporter :dialogue arm + round-trip, riding every export; C
(deterministic sfim) shipped tonight at 2,530 units through F24; D
(decontam re-run 0/25,112 clean + export refresh 12,466) done tonight.

**Phase E — the honest fork (Kamil):** after C, existing-corpus
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
