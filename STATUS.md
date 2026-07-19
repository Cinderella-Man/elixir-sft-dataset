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

### ▶️ ALL REMAINING ITEMS ARE KAMIL'S CALLS
### (the 2026-07-19 overnight runbook + roadmap Phases A–D completed in
### full — stories in docs/15; corpus proven by full sweep, all pushed)

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

**Standing decisions (Kamil, unchanged):** 110_002 keep packet
(--approve or delete; then retro_audit --only "110_002*" so its staged
growth lands); the strategic fork — Phase 3 (490 queued bases; ~57/1000
ideas realized is the binding constraint) vs a training/eval cycle on
the export (converts the parked questions — register monotony, shape
weights, difficulty curve, T2.6-proper's worth — into measurements).

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
