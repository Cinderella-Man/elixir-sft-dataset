# PROJECT STATUS

**GOAL (Kamil 2026-07-19): the existing families as extended and as high
quality as possible — the dataset must be GOLD. When everything below is
done and verified, this file becomes one line: "catch up finished, ready
to generate new tasks." Nothing else belongs here.**

Rules: CONTEXT.md HOW-WE-WORK. Done work lives in docs/15 + git history.
Finding details for the current campaign: `logs/semantic_review.jsonl`
(machine) + `docs/19-gold-defect-triage.md` (hand work).

---

## NEXT ACTIVITIES (in order)

1. **[DONE except retry pass → see 2] close_gaps campaign.** Batch
   1/HIGH: 27/31 applied (61 tests). Remainder: 111/155 applied (+253
   tests). Campaign: 138/186 families, 314 tests, all gate-arbitrated;
   resync sweeps + pushes done after each batch.

**NIGHT RUN 2026-07-21/22 — full lane map (parallelism audit
2026-07-21 23:35):**
- **LLM lane 1:** rubric_judge FULL PASS riding (pid in
  `logs/rubric_judge_full.pid`, ~22/320 at 23:30, monitor armed).
- **LLM lane 2 (short jobs):** 020_004 salience candidate verifying
  via keep_land (the prompt-fix batch COLLAPSED to this one — hand
  checks overturned the judge's NOT-ENTAILED on 005_003 (line 46
  documents topic-drop verbatim) and 074_002 (line 5 documents
  missing-element listing), and my own shallow 041_004 read (line 53
  'derive ETS table names' entails per-instance tables): all three =
  entailed-hard, G9 seeds, no prompt churn. Judge scorecard on
  NOT-ENTAILED verdicts: 1 right, 3 wrong — hand-verify always.)
- **CPU lane:** G2 re-measure riding (`validate --semantic-mutants`,
  pid in `logs/semantic_mutants_full.pid`, sha-resume; rebuilds the
  post-campaign tail for activity 5; 15-min monitor).
- **In-session: docs/19 HIGHS 12/12 DONE 2026-07-22** (9 fixed:
  035_001, 101_001, 074_001, 013_003, 040_003, 015_004, 019_004,
  061_001, 045_002; 3 refuted-stale: 031_002, 095_003, 040_001).
  045_002 closed the set: persistent_term routing documented →
  blind-green first try → both close_gaps tests landed 24/24 →
  rescreen green. Staleness sweep refuted 5 mediums; **NEXT: the 34
  live medium findings** (docs/19). G4 pre-classification DONE:
  `logs/sleep_audit_worklist.jsonl`.
- **Deliberately QUEUED (same-lane contention, not idleness):** G9
  probe + G5 sweep + rewrite_reachins all need the LLM lane — they
  queue behind rubric so the backbone finishes tonight; G8 gated by
  G3 by design; G3 rotation + G6 reads are hand-work behind docs/19.
- CLOSED tonight: G1a (dormant 25→0), G7 (full accounting), all 3
  stragglers, CI adapt-drift (family-wide resync rule memorized).

2. **[DONE 2026-07-22] Campaign follow-ups — every hand queue
   emptied** (blind-ADDED reads, solver-weak reads incl. the judge
   overturns, stragglers, DORMANT? reads, prompt-fix batch, S6/keep
   resolutions; details in docs/15-bound commits).
   - Mini-pass DONE: all 3 stragglers rejected with their SAME
     systematic reasons → hand queue (098_004 mold bitstring-pin bug,
     100_003 max_turns, 100_004 solver no-compile).
   - **Classifier bug FOUND + FIXED 2026-07-21** during the 018_001
     read: blind_gate matched bare `test "..."` names against
     ExUnit's describe-prefixed failure names, so every pre-existing
     failure inside a `describe` block read as "fails ADDED test(s)"
     — the whole "endpoint cluster" was this artifact. Fix in
     close_gaps.exs (describe-aware matching); the 13 flagged
     families re-partitioned deterministically from the ledger.
   - **Blind-ADDED hand-reads: 9 of 10 DONE 2026-07-21.** 8 landed by
     hand (020_002, 020_003, 022_002, 022_003, 025_002, 043_001 —
     initial over-pin call reversed on deeper read, 045_003, 108_003;
     +005_003 re-sorted from solver-weak and landed) — every one pins
     an explicit/verbatim prompt promise; candidates had passed all
     local gates, all re-graded green post-land with cascades.
     045_002 = REAL prompt defect (module-level API signatures make
     the :name/:table_name promises unexercisable) → docs/19.
   - **S6 CLOSED 2026-07-21: zero stale roots, push UNBLOCKED (commit
     e20224e59).** All 7 keep packets reviewed on the data and
     APPROVED (delegated; resolution rows carry the honest resolver);
     098_004 rescreened GREEN first try; the old 007_002/110_002
     packets were MOOT (improvements already in the current prompts).
     The 9 keep/hard families seed G9's probe set.
   - **DORMANT? hand-reads: 8/8 DONE, all FINE** (4 observe via
     assert_receive; 2 observe positionally; adapt_006_002 +
     adapt_023_004 specs explicitly FORBID timers — projection
     artifacts). lint_harnesses now scopes adapt_ timer detection to
     the new-spec section (6 false-positives cleared; remaining
     DORMANT? = the 2 verified-fine 015_001 projections). Same
     spec-scoping refinement owed to the S9 evaluator detector (lib
     edit — land in the next between-campaigns window). **Remaining
     G1a tail: enumerate the lint's 25 CONFIRMED dirs** (derivatives +
     never-applied roots; no campaign-applied root can be dormant —
     the S9 gate proved each apply).

3. **[ ] Hand-triage docs/19 — 63 gold/prompt-defect findings (11
   high, 52 families).** Top-down, one family = one commit + full
   cascade + re-grade. Never auto-strengthened.

4. **[ ] rubric_judge full two-family pass** over all roots (~330 LLM
   judge calls) — the last G1 instrument still owed.

5. **[ ] Weak-assertion tail (G2).** `strengthen_harnesses` the 27
   tasks under the 0.6 kill floor (report:
   `logs/semantic_mutants_full.log`), local re-measure, then promote
   the floor to a failing check in validate/CI.

6. **[ ] Harness style debt (G4).** `rewrite_reachins` the 52
   `:sys.get_state` harnesses; audit the 142 `Process.sleep` users
   (legit timing contract vs needs-injected-clock); includes the
   tfim_107_002 stability-3 hard fail (reproduce under parallel load,
   fix or document the timing contract).

7. **[ ] Prompt-register variety (G3).** Template rotation for the
   six templated shapes (deterministic, no LLM), then LLM register
   rewrites of monotone seed prompts, each with a mandatory blind
   re-screen. Wire rotation into the generator templates too.

8. **[ ] @doc prose truth on existing golds (G5).** Sweep @doc claims
   vs prompt contract; un-promised claims get prompt sentences +
   anchored tests (promise-audit machinery) or get cut.

9. **[ ] Family spot-checks (G6, CONTEXT rule 8).** Structured hand
   READS of sampled families across eras/shapes, both accepted and
   rejected sides; notes ledgered.

10. **[ ] Repair-pair recovery (G7).** Run `mint_repairs.exs` (local
    grading; why-ledger `logs/repair_unverified.jsonl` — rule-9 pilot
    the first rows), investigate the 134 unverified pairs, recover
    what's honestly recoverable.

11. **[ ] Screen depth (G9) — decide by probe.** Run 3-solve
    consistency on 10 of the ~50 keep/hard roots; if the 3-solve
    verdict diverges from the recorded single-solve verdict on ≥2 of
    10, run all 50 and update the difficulty metadata; otherwise close
    the item with the probe evidence.

12. **[ ] Extension headroom (G8) — DECIDED in scope** (the goal
    literally says "extended"; deciding by probe, not by asking).
    Probe first: 2 strong base families × 1 new variation each through
    the full loop, then the SAME instruments that found this month's
    debt (semantic_review on the new roots + a rubric spot-judge);
    acceptance = zero triage-grade findings (the docs/12 §5.5 bar).
    Pass → size and run the extension loop as the LAST activity before
    the finish line (so new mints carry every gate from activities
    2-7, incl. the varied register). Findings → fix the generator,
    regenerate, re-probe. Probe earliest after activity 7.

13. **[ ] Finish line.** Full sweeps (perfect + fim + mutants +
    decontam), export refresh, README — then this file becomes the
    one-liner. (The docs/18 training-run handoff stays available to
    Kamil at any time; gold-first proceeds regardless.)
