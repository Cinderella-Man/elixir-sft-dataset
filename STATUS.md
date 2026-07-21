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

2. **[IN PROGRESS] Campaign follow-ups. MACHINE PHASE FINAL:
   159/182 families applied (87%), 23 open — all with human-shaped
   reasons.** (Passes 1-3 done; commit cc50ffd51.)
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
   - **[ ] 005_003 prompt-fix** (rescreen judge: NOT ENTAILED — the
     current prompt under-specifies its own pre-existing topic-drop
     test; verify the judge's reading by hand, then prompt sentence +
     re-screen).
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
   - **[ ] 8 solver-weak repeaters → hand-read** (005_003, 007_002,
     013_003, 020_004, 031_001, 032_001, 041_004, 074_002): repeated
     solver failures on PRE-EXISTING tests — decide hard-task
     (document, feeds G9 difficulty metadata) vs a genuine trap.
     **Plug.Parsers hypothesis REFUTED by A/B experiment 2026-07-21**
     (gold ± `Plug.Parsers [:json]` both 31/31 green — Parsers no-ops
     on Plug.Test's pre-fetched map-posts; no wiring trap exists).
     018_001 + 019_001 dispositioned: hard multifile Phoenix families,
     solver variance — they seed the G9 3-solve probe set (activity
     11). NOTE for reads: reject details truncated failing names at 4
     (now fixed to carry counts) — do not assume only 4 tests failed.
   - **[ ] 3 systematic stragglers → hand-fix** (098_004 write the
     harness fix by hand; 100_003/100_004 investigate why this
     family's content blows the solver).
   - **[ ] Hand-read the 8 DORMANT? timer dirs** (015-family +
     adapt_107_004 likely fine; adapt_023_004 + adapt_006_002 likely
     real).

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
