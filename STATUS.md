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

1. **[DONE 2026-07-22] MERGED HAND QUEUE (activities 3+4) — CLOSED.**
   All 11 rubric triage roots fixed; every docs/19 finding DONE or
   refuted with artifact evidence; 032_002 re-judged clean on its
   fixed sha (4/4/4, 4/5/5 — the errored row superseded). Full record
   in docs/15 + the commit chain. Standing lessons now in force:
   per-finding evidence checks on any sweep refutation; bugfix
   children + repair_/dialog_ copies checked on EVERY gold edit (the
   pre-push perfect sweep is the backstop); stage with git add of the
   tasks tree, never bare multi-globs.

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
