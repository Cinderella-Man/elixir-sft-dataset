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


### 🔎 OPEN FINDINGS

**110_002 is KEEP-CLASS at the rolling-window-expiry hard spot —
strengthen-path queue (2026-07-18).** Four independent solver samples
failed "slices outside the window are excluded" in one day (grown
harness r4+r5, current harness fallback, plus the 07-17 standing red).
Three surgical prompt improvements were written and each demonstrably
fixed a distinct solver failure mode (series-vs-server addressing
killed the :noproc class; caller-side validation raise killed the
ArgumentError-EXIT class; the slot-expiry mechanism sentence) — but the
expiry test still reds, so per the gate nothing landed: prompt reverted,
improved version SAVED at
`logs/retro_audit_backup/110_002_precision_candidate_20260718.md`.
Blocked on the same strengthen path as the other keep-class roots. Also
blocked behind it: the audit's repeatedly-proven growth (8→13/14 tests
incl. a proven-defect gold repair, all gates green in staging four
times). When the strengthen path exists: land the saved prompt via
Kamil-reviewed keep, then re-run retro_audit on the root.

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
COUPLING (2026-07-19 review): `GenTask.Prompts` sits in the gate-sha of
BOTH `prompt_precision.jsonl` and `retro_audit.jsonl` row keys, so ANY
Prompts edit re-opens ~650 LLM-priced verdicts for future resumes —
batch this one-sentence rule with the next deliberate Prompts change
(the Phase-3 template pass), never as a solo edit.

**retro_audit row-key gap (Task B pending):** the row key omits the
script's own bytes (gate_sha covers the four judged modules only —
prompt_precision.exs hashes its own file and is the right pattern);
fold the alignment in at the next deliberate ledger re-open, NOT now
(adding it now would silently re-open all 314 sound verdicts). Also
park there: 3 chronic compile-artifact roots (071_001, 100_002,
100_003 — long-solution blind replies truncate 3/3 samples; a
continuation-aware blind solve would unlock their promise audits).

**PARITY TABLE: ZERO hard pre-Phase-3 blockers remain (2026-07-19).**
Rows 15+23 closed on Kamil's go with the ACCEPT-PATH carrier (the
stronger option per "quality gates are never optional"): the
T1.6-calibrated analysis now lives in `GenTask.Dialyzer`, wired as
Cycle gate 4 (default-ON `GEN_DIALYZER`, warnings reject + feed the
repair prompt; repair coverage falls out of the suite re-running per
attempt). Every remaining row reads ENFORCED or has its defined
post-cutover path (11/12/16/17/21 — see the table). What still gates
Phase 3 is the PROCESS list in "Current mode" below (loop-parity now
done; cutover acceptance test on the first batch; the §7.2 line),
plus Kamil's standing decisions (strays, follow-up C).

### 🔨 BUILDS

**KEEP PACKETS PENDING KAMIL (`scripts/keep_land.exs`, built
2026-07-19):** review each packet in `logs/keep_review/<root>/`
(candidate vs current prompt, first failure, judge verdict) and either
`mix run scripts/keep_land.exs -- --approve <root>` (lands + writes the
keep resolution row; then cascade + commit) or delete the packet.
Pending now: 007_002_weightedmovingaverage_01 (guard-sentence
candidate; blind red at the WMA-weighting test whose formula the
candidate states VERBATIM — judge quoted it; textbook solver-weak
keep). 110_002_histogram_based_approximate_rolling_percentile_01
(the three-fix candidate from the T2.6 rounds; blind red was the
SOLVER crashing on :array.new badarg — solver-weak, nothing prompt-side
— judge ENTAILED quoting the estimation-algorithm paragraph). After
approving 110_002, re-run
`mix run scripts/retro_audit.exs -- --only "110_002*"` so its
four-times-staging-green growth (incl. the proven gold-defect repair)
gets its landing chance against the improved prompt.

### 🔎 OPEN FINDINGS

**F23 Task B (batched with F22 at the next deliberate Prompts edit):**
the LIFECYCLE RULE gains the sub-case "a manual/external trigger must
not arm a second periodic chain — it folds into the existing one".
Task A closed 2026-07-20: gold fixed (cancel-before-re-arm single-timer
invariant + stale-tick drain), harness grew the two pins (old gold
fails exactly the orphan pin), full cascade + pairs remint, all gates
green; the blind red on the new pin is the family's standing keep
class (third independent solver reproducing the F17-1 mistake),
covered by the existing triage keep verdict at this prompt sha.

### 🧑‍⚖️ WAITING ON KAMIL

**Optional follow-up C (low priority):** 009_003 balanced rewording
(candidate's caller-blocks emphasis needs a "server loop stays
responsive" counterweight), 007_002 guard sentences via strengthen path,
014_001/044_001 fresh editor retries (token-vet fired; needs a
ledger-row removal or tool change to re-run).


### 🔎 OPEN FINDINGS

**110_002 is KEEP-CLASS at the rolling-window-expiry hard spot —
strengthen-path queue (2026-07-18).** Four independent solver samples
failed "slices outside the window are excluded" in one day (grown
harness r4+r5, current harness fallback, plus the 07-17 standing red).
Three surgical prompt improvements were written and each demonstrably
fixed a distinct solver failure mode (series-vs-server addressing
killed the :noproc class; caller-side validation raise killed the
ArgumentError-EXIT class; the slot-expiry mechanism sentence) — but the
expiry test still reds, so per the gate nothing landed: prompt reverted,
improved version SAVED at
`logs/retro_audit_backup/110_002_precision_candidate_20260718.md`.
Blocked on the same strengthen path as the other keep-class roots. Also
blocked behind it: the audit's repeatedly-proven growth (8→13/14 tests
incl. a proven-defect gold repair, all gates green in staging four
times). When the strengthen path exists: land the saved prompt via
Kamil-reviewed keep, then re-run retro_audit on the root.

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
COUPLING (2026-07-19 review): `GenTask.Prompts` sits in the gate-sha of
BOTH `prompt_precision.jsonl` and `retro_audit.jsonl` row keys, so ANY
Prompts edit re-opens ~650 LLM-priced verdicts for future resumes —
batch this one-sentence rule with the next deliberate Prompts change
(the Phase-3 template pass), never as a solo edit.

**retro_audit row-key gap (Task B pending):** the row key omits the
script's own bytes (gate_sha covers the four judged modules only —
prompt_precision.exs hashes its own file and is the right pattern);
fold the alignment in at the next deliberate ledger re-open, NOT now
(adding it now would silently re-open all 314 sound verdicts). Also
park there: 3 chronic compile-artifact roots (071_001, 100_002,
100_003 — long-solution blind replies truncate 3/3 samples; a
continuation-aware blind solve would unlock their promise audits).

**PARITY TABLE: ZERO hard pre-Phase-3 blockers remain (2026-07-19).**
Rows 15+23 closed on Kamil's go with the ACCEPT-PATH carrier (the
stronger option per "quality gates are never optional"): the
T1.6-calibrated analysis now lives in `GenTask.Dialyzer`, wired as
Cycle gate 4 (default-ON `GEN_DIALYZER`, warnings reject + feed the
repair prompt; repair coverage falls out of the suite re-running per
attempt). Every remaining row reads ENFORCED or has its defined
post-cutover path (11/12/16/17/21 — see the table). What still gates
Phase 3 is the PROCESS list in "Current mode" below (loop-parity now
done; cutover acceptance test on the first batch; the §7.2 line),
plus Kamil's standing decisions (strays, follow-up C).

### 🔨 BUILDS

**KEEP PACKETS PENDING KAMIL (`scripts/keep_land.exs`, built
2026-07-19):** review each packet in `logs/keep_review/<root>/`
(candidate vs current prompt, first failure, judge verdict) and either
`mix run scripts/keep_land.exs -- --approve <root>` (lands + writes the
keep resolution row; then cascade + commit) or delete the packet.
Pending now: 007_002_weightedmovingaverage_01 (guard-sentence
candidate; blind red at the WMA-weighting test whose formula the
candidate states VERBATIM — judge quoted it; textbook solver-weak
keep). 110_002_histogram_based_approximate_rolling_percentile_01
(the three-fix candidate from the T2.6 rounds; blind red was the
SOLVER crashing on :array.new badarg — solver-weak, nothing prompt-side
— judge ENTAILED quoting the estimation-algorithm paragraph). After
approving 110_002, re-run
`mix run scripts/retro_audit.exs -- --only "110_002*"` so its
four-times-staging-green growth (incl. the proven gold-defect repair)
gets its landing chance against the improved prompt.

### 🔎 OPEN FINDING — F23 (rubric panel's first real catch, triaged
### CONFIRMED against the code 2026-07-20)

**015_001_heartbeat_monitor_01: `handle_info({:check, name})` re-arms
the timer unconditionally whenever the service is in the map.** Two
proven consequences: (a) the DOCUMENTED manual `{:check, name}`
message ("performs one check") arms a SECOND live chain — check
cadence doubles permanently, a timer leak; (b) a stale in-flight
check surviving deregister→re-register finds the NEW registration and
arms a duplicate chain — the deregister comment's "discarding is
sufficient" invariant is false under re-registration. Both judges
flagged logical_correctness independently with these exact mechanisms;
code reading confirms. The harness never pins either interleaving —
that is WHY every execution gate passed.
**Task A (fresh session):** fix = generation-tag the scheduled
messages (`{:check, name, ref}`; re-arm only on ref match; the bare
2-tuple manual form checks WITHOUT re-arming — the same
generation-ref pattern probe #4's roots already use), grow the
harness to pin manual-no-rearm + stale-after-rereg, then the FULL
solution-change cascade (bugfix pairs remint, fim/wt/tfim/dedoc/
dialog children, dialyzer re-verdict). Prefer driving it through
`retro_audit --only "015_001*"` after the gold fix so the machinery
proves + cascades safely.
**Task B:** the LIFECYCLE RULE gains the sub-case "a manual/external
trigger must not re-arm the periodic chain" — batches with the F22
sentence at the next deliberate Prompts edit.

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
