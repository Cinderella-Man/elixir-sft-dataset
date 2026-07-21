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

1. **[IN PROGRESS] close_gaps campaign — remainder batch (155
   families).** Detached pid: last line of `logs/close_gaps_full.pid`,
   log `logs/close_gaps_full.log`, ledger `logs/close_gaps.jsonl`.
   Idempotent relaunch: `scripts/run_detached.sh
   logs/close_gaps_full.log mix run scripts/close_gaps.exs -- --go`.
   Batch-end contract: unscoped resync sweep (all
   `scripts/resync_*_embeds.exs` + `resync_sfim_specs.exs`, `--apply`)
   → commit+push → sample-review applied diffs → collect rejects.
   (Batch 1/HIGH done 2026-07-21: 27/31 applied, 61 tests.)

2. **[ ] Campaign follow-ups.** One retry pass for INCONCLUSIVE
   rejects; hand-check 102_001 if its added-test blind failure repeats;
   hand-read the 8 DORMANT? timer dirs (015-family + adapt_107_004
   likely fine, adapt_023_004 + adapt_006_002 likely real); pre-flight
   refusals (reach-in debt) feed activity 6.

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
