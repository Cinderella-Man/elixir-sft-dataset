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

**STEP 2 — follow-up C landings (Kamil approved 2026-07-19; candidates
are DRAFTED and verified-by-diff in `logs/followup_c_candidates/`).**
[IN FLIGHT 02:02: candidate 1 (009_003) running detached —
logs/keep_land_009_003.log; the three run SEQUENTIALLY (keep_land must
never run concurrently with another prompt-writing tool), each lands on
green / packets on red, cascade + one commit per landing; 007_002
--approve last.]
For each of the three, run the keep path (1 blind solve each; lands on
green, judge-packet on red — never lands unverified):
`mix run scripts/keep_land.exs -- --candidate 009_003_retry_aware_request_deduplicator_01 --prompt logs/followup_c_candidates/cand_009_003.md`
`mix run scripts/keep_land.exs -- --candidate 014_001_priority_queue_processor_01 --prompt logs/followup_c_candidates/cand_014_001.md`
`mix run scripts/keep_land.exs -- --candidate 044_001_ets_based_metrics_collector_01 --prompt logs/followup_c_candidates/cand_044_001.md`
Then the directed approval (Kamil's 2026-07-19 message names 007_002):
`mix run scripts/keep_land.exs -- --approve 007_002_weightedmovingaverage_01`
FAMILY SWEEP ALREADY DONE: all siblings of 007/009/014/044 verified
precise (test-name-vs-prompt scan; the suspicious greps all resolved to
already-stated semantics). After any landing: the standing cascade
(resync_embeds --wt-all, resync_bugfix/tfim/adapt/dedoc, check_embeds)
+ commit per landing.

**STEP 3 — refresh + close.**
`mix run scripts/export_dataset.exs` + `-- --check`; update README's
at-a-glance numbers (will be ~12,300 examples / count `_0N` via the
export report's shape table; keep the conservative framing sentence);
docs/15 entry for: sfim shipped (tally from both logs), carver-bug
story, follow-up C closed. Push.

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

**Phase A — running now (automatic):** tfim cap-lift backfill → rubric
pass #2 → triage any both-judge lows against artifacts (rule 7).

**Phase B — TD.2 multi-turn repair dialogues (~86 chains).** The ONLY
shape that teaches iterative repair (spec → failing attempt → failure
report → fix). Deterministic from the archived chains; per-pair
re-verification like mint_repairs. Needs first: the multi-turn export
format written into docs/16 (proposal: standard chat turns, gold = the
accepted final attempt, earlier turns loss-masked by the training-run
convention — documented, not enforced by us).

**Phase C — deterministic sfim (~2,737 code-FIM units) — DESIGN
CAPTURED 2026-07-20, build queued for a fresh session.** The last big
volume lever; templated register precedented by tfim/adapt/dedoc/style.
Reuse points verified in code: `GenTask.Fim.fn_targets/1` (AST-based
target enumeration incl. multi-clause `{name, arity}`),
`covered_targets`/`excluded_targets` + the fim-reject ledger,
`EvalTask.Fim.build_skeleton/2` (the resync-gate-proven skeleton
builder), and `GenTask.Fim`'s three mint gates (skeleton integrity,
reconstruction green + 0 warnings, gutted-candidate mutant kill). The
deterministic variant = Fim with the LLM's two roles replaced:
target selection → ALL uncovered public/private carvable targets
beyond the LLM-fim children (fim_max_per_task=3 stays the LLM bound);
prompt prose → a template modeled on tfim's (name the function, its
callers/callees context is already in the embedded skeleton). Units
keep the existing `_0N`/`:fim` shape — NO new shape integration
needed (exporter/freshness/resync already handle :fim; module-FIM
resync covers regenerability). Standalone miner
`scripts/mint_sfim.exs` (mint_style pattern: census → pilot →
detached full mint, sha-keyed reject ledger, canonical writes via mix
format semantics — remember the two-canons and zero-warnings lessons
from TD.4/TD.2). Expected yield ~2,000-2,700 after gates.

**Phase D — training-readiness hygiene:** decontam RE-RUN over the
grown corpus (first pass was clean 0/786 but predates ~1,100 new units
— cheap CPU, standing pre-export check), export refresh, full sweep.

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
