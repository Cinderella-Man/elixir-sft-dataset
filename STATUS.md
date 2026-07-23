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

3. **[DONE 2026-07-22] Weak-assertion tail (G2) — CLOSED, floor
   PROMOTED.** Machine phase 7/9; hand-tails 064_001 (0.82) + 071_001
   (0.67); nine repair_-dir pairs refreshed and verified both sides;
   corpus re-measure: 0 families < 0.5, sub-0.6 tail = the two 037
   anonymizer families, PROVEN at ceiling (survivors live in the
   {:fake, seed} derivation arithmetic the prompt deliberately leaves
   unspecified — S6-unpinnable). validate.exs --semantic-mutants now
   FAILS below 0.6 for non-waived non-wt families (waivers are
   recorded verdicts with evidence; bite-proven both ways) and runs
   in weekly CI off the committed ledger. The strengthen-archiving
   Task-B rider is closed-as-moot: the tool retires at the line and
   the floor gate is the standing protection.

4. **[DONE 2026-07-22] Harness style debt (G4) — CLOSED.**
   The :sys.get_state/replace_state purge ALREADY RAN 2026-07-14 (34
   applied rows in logs/rewrite_reachins.jsonl; zero reach-ins on
   disk — the old "52" counted the 102-family's DOMAIN-API get_state/2
   and derivative copies; :sys.suspend/resume uses are deliberate
   stall-testing, not reach-ins). Remaining:
   (a) DONE 2026-07-22: sleep audit CLOSED — the 38 suspicious files
   collapse to 18 unique parents (rest are wt_/repair_/dialog_
   mirrors) and EVERY sleep is a sanctioned class (bounded poll
   helpers, payload sleeps, 013-family tick-catch-up, 015-family
   real-timer waits, 023-family clock-set-then-real-sweep hybrids);
   none masks a missing clock advance. Verdict row appended to
   logs/sleep_audit_worklist2.jsonl with per-family classes;
   (b) DONE 2026-07-22: the tfim_107_002 hard fail was child _11's
   STALE GOLD still asserting the pre-widening 1ms upper tolerance
   (elapsed < 1_001_000 on a real 1s timer — a 5us overshoot under
   parallel load failed it); the parent test had already been widened
   to 1_500_000 with the jitter rationale. Gold re-carved from the
   current body (raw slice, <=98 cols), 1.0 x4;
   (c) DONE 2026-07-22: S9 evaluator timer-detection spec-scoping
   landed (content-keyed contract_text; 3 unit tests; 415 green).
   The post-flip full re-measure LANDED 2026-07-23: 663 tasks,
   corpus kill 83.7% (mean per-task 0.853), floor gate EXIT 0 with
   only the two waived 037 families below 0.6 — ledger sha-current
   for the weekly CI gate.

5. **[ ] Prompt-register variety (G3).** DETERMINISTIC HALF DONE
   2026-07-23: 3-variant register rotation landed in all NINE
   template modules (bugfix/wt/adapt/dedoc/tdd/tfim/sfim/specfim/
   bundlefim; single source for mint AND resync), selection =
   phash2(dir basename, 3) via GenTask.Register; variant 0 = the
   pre-rotation bytes (golden-fixture-tested). Corpus rotated via
   the resync battery: 8,735 prompts resynced / 4,472 kept v0;
   all dry-runs back to 0; all nine self-tests bite (sfim's plant
   made variant-agnostic); embeds 3889/0/0; format 0; sampled
   perfect validate 1.0 across every rotated shape; S6 fresh 332;
   6 new property/golden tests (423 total green). NOTE: the mint
   modules' md5 bump auto-reopens their reject ledgers (docs/12
   §5.1.12) — next topup visits re-converge them at identical
   verdicts, bounded local-eval cost.
   REMAINING (the LLM half): register rewrites of the ~305 monotone
   seed prompts (301/332 open "Write me an Elixir", census
   2026-07-23), each with a mandatory blind re-screen + full family
   embed cascade; detached + sha-ledgered.
   DESIGN CONSTRAINTS (verified 2026-07-23 before implementing):
   (a) the machinery PARSES structural markers inside these prompts —
   "## New specification" (adapt: resync + lint + evaluator
   contract_text), "## Module under test" (wt), "## The module"
   (dedoc), "## The task" — rotation must vary the PROSE around
   markers and NEVER the marker lines themselves, or shape detection
   breaks corpus-wide; (b) variant selection must be DETERMINISTIC
   from the unit id (id-hash mod N) so resyncs reproduce bytes;
   (c) generator template modules and the resync tools must share ONE
   source of truth per shape (the template modules in lib/gen_task/),
   so rotation lands there and both paths inherit it; (d) fim/tfim
   "# TODO" blank markers and the fence layout are carver contracts —
   frozen; (e) after rotation, the full resync battery regenerates
   derivative prompts and check_embeds/format gates must stay 0/0;
   (f) DISCOVERED 2026-07-23 pre-implementation: THREE MORE frozen
   anchor classes — specfim's resync recovers name/arity from the
   PROSE SENTENCE "the `@spec` for `X` has been removed" (regex with
   \n? wrap tolerance); the numbered-namespace shapes are sniffed by
   H1 TITLE LINES ("# Implement the missing function"/"...file" in
   format_corpus.exs shape pairs + resync_sfim/bundlefim sniffers)
   alongside their interpolated headings ("## The module with `X`
   missing" / "## The bundle with `X` missing"); and rotated prose
   in contract_text scope (wt/tfim/dedoc BEFORE-marker prose; whole
   prompt for bugfix/tdd) must never add Process.send_after or
   :interval/:period vocabulary (S9 timer-scan tokens). Full frozen
   inventory + variant design: docs/20-register-rotation-design.md.

6. **[ ] @doc prose truth on existing golds (G5).** Sweep @doc claims
   vs prompt contract; un-promised claims get prompt sentences +
   anchored tests (promise-audit machinery) or get cut. (The hand
   queue in item 2 fixes many @doc-contradiction findings — check
   what the sweep still owes after it.)
   SIZED 2026-07-23 (sha cross-check of semantic_review latest rows):
   5 roots have doc-claim findings measured on CURRENT bytes; 14 more
   rows are stale (solution sha changed since review — presumed fixed
   by the docs/19 doc-truth batch; confirm per-finding on artifact
   reads, standing lesson). The full sweep is a NEW dedicated
   @doc-truth pass over all roots (semantic_review was not
   doc-focused), detached + sha-ledgered, after G3.
   PILOT FIXES APPLIED 2026-07-23 (all 5 golds edited, each re-graded
   1.0; embeds cascaded: wt 5 / tfim 93 / adapt 4 / dedoc 5 / tdd 5 /
   specfim 27 resynced, 8 fim-child golds hand-re-carved from the new
   parents (the fix_child_gold class), one historical stray blank in
   062_001_03's embed removed — check_embeds 3889/0/0). RIDING: 15
   bugfix pairs deleted, topup remint launched detached
   `scripts/run_detached.sh logs/topup_g5_remint.log bash -c 'for i
   in 5 32 62 97 99; do GEN_ONLY=topup GEN_SKIP_VARIATIONS=1
   GEN_SKIP_FIM=1 mix run scripts/generate.exs $i; done'` — verify
   after: gate 0 stale_gold, audit_bugfix 15/15, scoped validate.
   Original findings:
   - 099_004: moduledoc says stats/0, API is stats(server)/1 —
     one-token doc fix.
   - 062_001: @doc on run/2 claims failed-stage timing recorded;
     prompt says error tuple "carries no metadata list"; code agrees
     with prompt — rewrite the @doc sentence.
   - 097_002: prompt promises a SINGLE public function; gold exports
     public levenshtein/2 with @doc false (harness never calls it) —
     make defp.
   - 005_003: fresh Process.monitor ref per subscribe makes the
     Map.update merge fn + the remaining!=[] branch UNREACHABLE;
     moduledoc advertises %{ref => {pid, [topic, ...]}} multi-topic
     shape that is always a singleton — simplify to singular shape,
     both handlers + moduledoc.
   - 032_003: prompt MANDATES a streaming pipeline; gold Enum.reduces
     all parsed records into memory then chunk_every's (moduledoc
     "never loads the full file" is false) — real fix: lazy
     chunk-carried-counter pipeline (Stream.chunk_while + bounded
     async_stream), results identical, memory bounded. Largest of
     the five.

7. **[DONE 2026-07-23] Family spot-checks (G6, CONTEXT rule 8) —
   CLOSED.** Deterministic sha-ordered stratified sample (seed string
   "g6-2026-07-23", reproducible): 10 accepted units across all 10
   strata (manual-era base, generated-era base, wt, tfim, bugfix,
   repair, adapt, dedoc, tdd, specfim) — ALL PASS on detailed reads;
   3 rejected verdicts probed SOUND (2 bugfix mutant-survivor rejects
   verified against harness reality, 1 sfim vacuous-target reject);
   1 whole-family read (044_002, 32 dirs) coherent. Zero new
   defects. Ledger: logs/g6_spotchecks.jsonl (14 rows). Standing
   practice (rule 8) continues at every future accept/reject tool.

8. **[IN PROGRESS 2026-07-23] Screen depth (G9) — PROBE DIVERGED,
   full run launched.** Probe result (3 passes × 10 roots, ledgered
   in screen_blind.jsonl): **5 of 10 roots diverge** (≥2/3 fresh
   solves GREEN on recorded hard-keeps; 108_003 went G-G-G) — same
   prompt shas, so single-solve luck, not prompt drift; the recorded
   difficulty labels are unreliable. Per the pinned rule: 3-solve ALL
   27 current hard-keeps. Remaining 17 roots (list: scratchpad
   g9_rest.txt) LAUNCHED detached: logs/g9_full.log — 3 sequential
   --rescreen passes over the 17-root glob; relaunch idempotent.
   AFTER: fold last-3 verdicts per root across all 27, update the
   difficulty metadata (locate its home — export weights / triage
   ledger) and close with the evidence.
   (Superseded probe launch record:)
   Current standing hard-keep set is 27 roots (not ~50 — the rest
   were fixed + re-screened green since): red latest screen row at
   the CURRENT prompt sha AND entailed-keep in screen_triage.
   Deterministic 10-root sample (seed "g9-2026-07-23", list in
   scratchpad g9_sample.txt): 041_004, 007_002, 100_003, 013_002,
   020_004, 101_003, 020_002, 020_003, 017_001, 108_003.
   Probe = 3 fresh blind solves each (screen_blind_solve --rescreen,
   3 sequential passes, solver=opus, same instrument+ledger as the
   originals — probe rows are legitimate screen evidence; S6 stays
   sha-fresh). Detached: logs/g9_probe.log; relaunch idempotent
   (each pass appends; count last-3 rows per root at analysis).
   DECISION RULE: a root DIVERGES if ≥2 of its 3 fresh solves go
   green (single-solve red was luck/solver weakness); ≥2 of 10
   divergent roots → run all 27 and update difficulty metadata;
   else close on probe evidence.

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
   FAMILIES SELECTED 2026-07-23 on ledger evidence: ideas 91 + 65 —
   both at 1.00 MIN semantic-kill across every measured root (the
   only ideas at a perfect floor besides 34), 4 variations each on
   disk, domain-diverse (91 data-driven FSM engine / 65 saga
   orchestration). Probe = one new variation each (next free b)
   through the standing loop.

10. **[ ] Finish line.** Full sweeps (perfect + fim + mutants +
    decontam), export refresh, README — then this file becomes the
    one-liner. (The docs/18 training-run handoff stays available to
    Kamil at any time; gold-first proceeds regardless.)
