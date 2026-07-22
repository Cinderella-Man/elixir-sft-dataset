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

1. **[ ] MERGED HAND QUEUE (activities 3+4): rubric triage + docs/19
   mediums — one visit per family, one commit each, full cascade +
   re-grade, hypotheses verified against artifacts (docs/14 rule 10).**
   (Judge-error scoped re-run DONE 2026-07-22: 4 roots re-judged, NO
   new triage; 032_002's sonnet judge hit error_max_turns again —
   re-judge it once AFTER its prompt fix lands, not before. DONE so
   far — see commits: 015_002, 013_002 (keep landed, 2 solver-error
   reds), 045_001, 015_004 (maintenance-timer sibling hole), 096_001
   (4 findings; NOTE its changes rode inside commit 2a7cdb327 whose
   message says 015_004 — full 096_001 story in docs/15). Also done:
   005_002 (sweep's refutation was WRONG — per-finding evidence
   checks now mandatory), 004_003 refuted-stale.)
   - Rubric triage: ALL 11 ROOTS DONE (064_001 closed the set; its
     G2 hand-tail + 071_001's done with it — see commits).
   - [IN FLIGHT] corpus-wide semantic re-measure for the G2 floor
     promotion: pid 4113769, log logs/semantic_full2.log. Expected:
     sub-0.6 tail = only at-ceiling families. Relaunch:
     scripts/run_detached.sh logs/semantic_full2.log elixir
     scripts/validate.exs --semantic-mutants. When it lands: design
     the floor gate (observable-kill semantics per docs/14 §5.1.2,
     at-ceiling waivers), wire into validate.exs + CI (G2 item c);
     plus Task-B rider: strengthen_harnesses candidate archiving.
   - DONE additionally: 032_004 (4 findings), 013_003 medium
     (candidate landed), 041_002, 110_004 (both sweep-refutations
     WRONG — per-finding evidence checks are now the rule), 011_004
     (stale-timeout ref match + dead timers map removed + pool_size-0
     range fix + await documented), 003_003 (pure query + 3 anchors;
     refund CAP proven unobservable — at-ceiling, recorded).
   - 031_001 finding 2 is LIVE (dead schema_by_name computation —
     the wholesale sweep refutation covered only finding 1).
   - Recurring catch to keep checking on EVERY family visit: bugfix
     children lagging their parent gold (013_003, 5 families today)
     and repair_/dialog_ harness copies lagging (refresh + verify
     both sides; replace gold with parent only when the old gold
     fails the refreshed harness).
   - docs/19 live mediums (unchecked boxes in the doc; refuted-stale
     already excluded): 004_003, 013_003(med), 022_001, 022_004(×2),
     031_002(med), 031_003, 032_001, 032_002, 035_002, 038_001,
     040_001(×2 med), 041_002, 043_001, 043_003, 044_001(×3),
     061_001(med), 063_001, 063_002, 065_003, 071_001, 072_002,
     075_001(×2), 079_001, 080_001, 089_003, 091_003, 095_003(med),
     097_001, 103_003, 103_004, 107_002, 109_001, 110_002.
   - 095_003 + 032_002 only after the re-run exits (item 1).

3. **[ ] Weak-assertion tail (G2) — hand phase + floor promotion.**
   Machine phase closed (7/9). Remaining: (a) hand-write strengthening
   tests for 064_001 (4 rolls, 4 different documented-pin blind
   failures — hard-family profile) + 071_001 (3× honest below-floor);
   (b) repair_-dir harness refresh — 074_003/101_002/101_003/102_003
   pairs re-verified fix-green AND broken-non-green against their
   strengthened parents; (c) THEN promote the 0.6 floor to a failing
   check in validate.exs + CI (floor stays report-only until the
   corpus is clean under it). Task-B rider: strengthen_harnesses
   should archive rejected candidates like close_gaps does (064_001
   lesson).

4. **[ ] Harness style debt (G4).** `rewrite_reachins` the 52
   `:sys.get_state` harnesses; audit the 142 `Process.sleep` users
   (pre-classification DONE: `logs/sleep_audit_worklist.jsonl`);
   includes the tfim_107_002 stability-3 hard fail (reproduce under
   parallel load, fix or document the timing contract). Also owed
   here: S9 evaluator timer-detection spec-scoping for adapt_ (lib
   edit — land in a between-campaigns window; lint_harnesses already
   has it).

5. **[ ] Prompt-register variety (G3).** Template rotation for the
   six templated shapes (deterministic, no LLM), then LLM register
   rewrites of monotone seed prompts, each with a mandatory blind
   re-screen. Wire rotation into the generator templates too.

6. **[ ] @doc prose truth on existing golds (G5).** Sweep @doc claims
   vs prompt contract; un-promised claims get prompt sentences +
   anchored tests (promise-audit machinery) or get cut. (The hand
   queue in item 2 fixes many @doc-contradiction findings — check
   what the sweep still owes after it.)

7. **[ ] Family spot-checks (G6, CONTEXT rule 8).** Structured hand
   READS of sampled families across eras/shapes, both accepted and
   rejected sides; notes ledgered.

8. **[ ] Screen depth (G9) — decide by probe.** Run 3-solve
   consistency on 10 of the ~50 keep/hard roots; if the 3-solve
   verdict diverges from the recorded single-solve verdict on ≥2 of
   10, run all 50 and update the difficulty metadata; otherwise close
   the item with the probe evidence.

9. **[ ] Extension headroom (G8) — DECIDED in scope** (the goal
   literally says "extended"; deciding by probe, not by asking).
   Probe first: 2 strong base families × 1 new variation each through
   the full loop, then the SAME instruments that found this month's
   debt (semantic_review on the new roots + a rubric spot-judge);
   acceptance = zero triage-grade findings (the docs/12 §5.5 bar).
   Pass → size and run the extension loop as the LAST activity before
   the finish line (so new mints carry every gate from the items
   above, incl. the varied register). Findings → fix the generator,
   regenerate, re-probe. Probe earliest after item 5 (G3).

10. **[ ] Finish line.** Full sweeps (perfect + fim + mutants +
    decontam), export refresh, README — then this file becomes the
    one-liner. (The docs/18 training-run handoff stays available to
    Kamil at any time; gold-first proceeds regardless.)
