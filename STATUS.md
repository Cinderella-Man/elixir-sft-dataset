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
   REMAINING (the LLM half): TOOL BUILT + COMMITTED 2026-07-23
   (scripts/rewrite_seed_registers.exs — self-test 6/6, census 232
   eligible single-module monotone roots; per-root: deterministic
   register target, no-drift rewrite contract, token/number vet,
   MANDATORY blind re-screen, land + cascade + S6-fresh row;
   sha-ledgered logs/register_rewrites.jsonl, resumable).
   EXECUTION QUEUE (transport is serial — one LLM sweep at a time):
   1. after the G9 full sweep exits → rule-9 PILOT: `mix run
      scripts/rewrite_seed_registers.exs -- --limit 3`, hand-read
      all three rewrites in full + their cascades before trusting;
   2. G8 probe (short) next — see item 9;
   3. then the full 232-root sweep DETACHED overnight:
      `scripts/run_detached.sh logs/register_rewrites.log mix run
      scripts/rewrite_seed_registers.exs`; relaunch idempotent.
   ALSO QUEUED (lib edit, land when no generate.exs alive): the
   variations meta-prompt lacks the register-variety directive the
   base_task meta-prompt already carries — add it so G8's new
   variation mints vary their register too.
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
   PILOT CLOSED 2026-07-23: all 5 golds fixed + re-graded 1.0, full
   cascade (wt/tfim/adapt/dedoc/tdd/specfim embeds; 8 fim-child golds
   re-carved), 15 bugfix pairs re-minted (gate 961/0 stale_gold,
   audit 15/15 + random 12/12), perfect+mutants green, embeds
   3889/0/0. Rider gate fix: audit_bugfix's spec_included now checks
   CONTENT (parent prompt verbatim in the child) instead of the
   v0-only heading the rotation retired. REMAINING for G5: the full
   corpus @doc-truth sweep (LLM, detached; queue after the G3
   transport queue drains). Original pilot findings:
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

8. **[DONE 2026-07-23] Screen depth (G9) — CLOSED.** All 27 standing
   hard-keeps 3-solved (probe 10 + full 17, ledgered): **16 flip to
   blind_solvable** by last-3 majority (7 at G-G-G) and **11 stay
   keep_class** (8 at R-R-R — 020_002/3/4, 025_002, 040_001, 041_004,
   045_003, 064_001; 3 at single-green splits correctly kept hard).
   Task B landed earlier the same day: export difficulty tier =
   majority of last 3 verdicts (unit-tested), so the metadata updates
   itself at the next export refresh from these very rows. Full
   record → docs/15.

9. **[IN PROGRESS 2026-07-23] Extension headroom (G8) — PROBE LAUNCHING.**
   Lever LANDED (commit 4e1fe704a): variation slot count is Config-tunable
   (GEN_VARIATION_SLOTS, default 3); raising to 4 opens b=5 for an
   already-converged idea. ONE source of truth across Work/Variations/Catalog
   (all derive b in 2..(slots+1)); 359 gen_task tests green.
   FAMILIES: ideas 91 (data-driven FSM) + 65 (saga orchestration) — both at
   1.00 MIN semantic-kill on ledger evidence, base+3 variations on disk (b=1..4),
   no b>=5 anywhere in the corpus (verified). Dry plan (GenTask.CLI.plan, no LLM):
   at slots=4 ONLY the base 091_001/065_001 seed carries needs_variations?=true
   (missing = 4-3 = 1) → exactly one new variation each into slot b=5.
   PROBE = VARIATIONS-ONLY (all derived stages skipped so it mints only the two
   _01 roots being judged; Work.derived(cfg)=[] confirmed with the full skip set
   incl. GEN_SKIP_TDD). LAUNCH (detached, logs/g8_probe.log):
     mv logs/attempts aside first (surgical: keeps the corpus-wide
     maybe_mint_repairs step — 223 mintable/89 exist/134 candidate-new — OUT of
     the probe; restore + resolve the 134 separately after, see item 4c).
     bash -c 'export GEN_ONLY=topup GEN_VARIATION_SLOTS=4 GEN_SKIP_FIM=1
       GEN_SKIP_WRITE_TEST=1 GEN_SKIP_TEST_FIM=1 GEN_SKIP_BUGFIX=1 GEN_SKIP_ADAPT=1
       GEN_SKIP_DEDOC=1 GEN_SKIP_SFIM=1 GEN_SKIP_TDD=1 GEN_SKIP_SPECFIM=1
       GEN_SKIP_BUNDLEFIM=1; mix run scripts/generate.exs 91; mix run
       scripts/generate.exs 65'
   Relaunch idempotent (both variations add-only; a done b=5 is skipped).
   AFTER the two b=5 dirs land: restore logs/attempts; run the SAME debt-finding
   instruments on the two new roots — semantic_review.exs --single <dir> and
   rubric_judge.exs --single <dir>; acceptance = ZERO triage-grade findings
   (docs/12 §5.5 bar). Read both variations in FULL (rule 9). PASS → the
   generator produces gold NEW data; size + run the full extension loop as the
   LAST activity (mints every derivative + varied register). FAIL → fix the
   GENERATOR, regenerate, re-probe (never hand-fix the probe data).

   4c. **[ ] Pending repair-mint (found 2026-07-23 during G8 prep).**
   mint_repairs.exs --dry-run: 1098 attempt chains, 223 mintable (rejected→
   accepted) pairs, 89 already on disk (=~90 repair_ dirs), 134 candidate-new
   never minted. Likely most fail real verification (a "rejected" attempt that
   actually grades green teaches nothing → correctly skipped), but unconfirmed.
   RESOLVE after the G8 probe: run mint_repairs.exs (real, DETACHED — up to ~268
   evaluator grades) to definitively mint the truly-mintable ones + close the
   rest as correctly-skipped. Deterministic, add-only, idempotent, self-verifying
   (broken grades non-green AND fix grades green, both real evaluator). Review a
   sample (rule 9) + commit new repair_ dirs on their own.

10. **[ ] Finish line.** Full sweeps (perfect + fim + mutants +
    decontam), export refresh, README — then this file becomes the
    one-liner. (The docs/18 training-run handoff stays available to
    Kamil at any time; gold-first proceeds regardless.)
