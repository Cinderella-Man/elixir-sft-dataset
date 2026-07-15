# 12 — The quality standard, the remaining work, and the road to steady state

Date: 2026-07-10. Written in plain language (glossary: docs/11 bottom).

This doc consolidates everything that still has to happen from docs/10 and
docs/11, plus what a seven-way deep investigation of the repository found today
(generation-loop gate audit, retroactive-vs-forward parity audit, live corpus
measurements, a fresh-eyes 12-task expert review across eras, an external
best-practices survey, a script inventory, and a README fact-check). It answers
four questions:

1. **Is the corpus at one quality level?** No — §2 says exactly where it is not.
2. **What is "one quality level", precisely?** §3 defines a versioned standard.
3. **What work remains, in what order?** §4 (corpus) and §5 (generation loop).
4. **When and how do we stop "catching up" forever?** §7 — the line, the
   deletions, and the protocol for any future improvement round.

The always-current answer to "where are we?" lives in `/STATUS.md` — this doc
is the reference it points to.

---

## 1. How this relates to docs/10 and docs/11

- `docs/10` is the QA **campaign log** — what was found and fixed. Historical.
- `docs/11` is the **phase plan** — QA catch-up → one top-up run → new
  generation. Still the plan of record for ordering.
- **This doc** is the concrete work list inside those phases, the definition of
  the standard everything must meet, and the exit protocol. When an item here is
  done, tick it here and in `/STATUS.md`.

---

## 2. The parity verdict: quality levels ARE stratified by generation date

Kamil's suspicion ("various update levels were applied to various datasets —
they are NOT in line") is **confirmed**, with precision. The corpus splits into
an April 2026 era (families 001–104 plus, confusingly, 623–626 — family number
is NOT an age proxy; check git history) and a July 2026 era (105+, all wt_/tfim_
dirs, recent variations).

**What IS uniform corpus-wide** (retroactive + CI-enforced):

- Perfect-score raw invariants (compiles, 0 warnings, ≥1 pass, 0 fail, 0 error).
- Whole-solution raise mutants (every harness kills a fully-gutted solution).
- Canonical formatting (restored today — see §4.1 item 1).
- Child-prompt embed staleness (CI gate since 2026-07-10).
- Blind-solve screening of every seed prompt (300/303 screened: 251 green, 49
  documented hard-task keeps; only 099_002/3/4 unscreened — added last night).

**What is NOT uniform** — the ranked out-of-line populations:

| # | Population | Size | What's missing | Cost to fix |
|---|-----------|------|----------------|-------------|
| 1 | Seeds accepted before 2026-07-02 | ~122 of 303 seeds (+ their 302 wt_ copies whose "inherited coverage" note is false for them) | never passed the **per-function** mutation gate, only whole-solution | deterministic sweep, no LLM (§4.1 item 3) |
| 2 | Every GenServer seed | 157 of 303 seeds | `init/1` was **never** mutation-checked anywhere: the whole-solution mutant builder exempts it unconditionally (`lib/gen_task/mutation.ex:92`), so even the CI `--mutants` sweep is blind to it | same sweep (§4.1 item 3) |
| 3 | Weak-assertion tail | 19 families < 0.5 semantic-mutant kill, 68 < 0.6 (family-level, after removing stale wt_ duplicate rows) | tests pass the reference but wouldn't catch off-by-one / swapped-comparison bugs | LLM-assisted, ~$2–5/family (§4.2 item 3) |
| 4 | Early-era gold quality | sampled grade: April era B+/C+/**D**/B+ vs July era A-/A-/A-/A- | leaked LLM repair chatter in golds, a real gold bug, self-weakened tests, prompt/solution mismatches (§4.1 items 4–6) | mostly deterministic + small LLM |
| 5 | Harness style debt | 52 harnesses with `:sys.get_state` reach-ins (11 families, April-era); 142 harnesses use `Process.sleep` incl. July's 105_001 which has no fake clock at all | internals-pinning and timing-sensitive tests; 23/26 affected families passed the blind screen, so this is *deprioritized by evidence*, not resolved | decision §4.2 item 5 |
| 6 | 23 tfim children of bundle parents | 016_001×10, 021_001×10, 102_001×3 | minted under the old bare-`assert` regex, never re-checked by the 07-08 AST assertion gate | seconds, deterministic (§4.1 item 7) |
| 7 | Prompt register monotony | 2,396/2,396 tfim prompts share one opening line; 302/302 wt_ share one; 75.9% of seed prompts open "Write me" | one rhetorical register per shape — a documented SFT failure mode (frozen-template overfitting) | the big LLM item, own round (§7.4) |

Two structural-only notes, fine as they are but must stay documented: within-
family text leakage is 91.7% **by construction** (children embed parent text) —
train/val splits must group by family; and 59 exact-duplicate solution groups
exist across sibling FIM children (by construction of shared helpers).

---

## 3. The Quality Standard, version 1

"In line" means: **every task in the corpus passes the same checklist**, and the
checklist is versioned. Raising the checklist = starting an improvement round
(§7.3). This is Standard v1 — the bar the 2026-07 campaign has been building:

| # | Requirement | Enforced today at |
|---|-------------|-------------------|
| S1 | Raw perfect score: compiles, zero warnings, ≥1 test passed, 0 failed, 0 errored, full style analysis | loop (base/variation), CI full sweep |
| S2 | Harness kills the whole-solution raise mutant (not vacuous) | CI every push |
| S3 | Harness kills the raise mutant of **every public function, including GenServer `init/1`** | loop since 07-02 + retro sweep DONE 2026-07-10 (zero survivors); `--per-fn-mutants` re-runnable on demand |
| S4 | Files are canonical `Code.format_string!` output on the pinned toolchain | loop autoformat + CI |
| S5 | Child prompts byte-match regeneration from current parents | CI + pre-push |
| S6 | Seed prompt is blind-solvable (independent solve from prompt.md alone goes green) or is a triaged, documented hard-task keep | one-off sweep + in-loop for variations — **base accept-time screen missing (§5.2)** |
| S7 | Every harness assertion is entailed by a prompt sentence | indirectly via S6 + judge triage — no direct gate |
| S8 | Semantic-mutant kill rate measured and recorded; floor TBD after tail fixed | manual sweep, report-only |
| S9 | No harness anti-patterns: `:sys.get_state`, undocumented internal messages, undocumented `:infinity` options, `assert inspect(...)`, exact exception-message pins | manual lint script — **not gated (§5.1)** |
| S10 | No leaked assistant chatter in gold files (repair commentary, chain-of-thought, emoji markers) | **nothing checks this today (§4.1.4)** |
| S11 | Prompt/solution/harness free of overlap with public Elixir benchmarks (MultiPL-E humaneval-elixir + mbpp-elixir, McEval Elixir, Exercism Elixir track) | `validate.exs --decontam` (since 2026-07-10; report-only, 0 hits) |
| S12 | Acceptance provenance recorded: which gates were active, what mutation mode ran, attempts count | **runs.jsonl records none of it (§5.1)** |

The steady-state goal (§7): S1–S12 all enforced by the loop or CI, so a task
that exists = a task that passed the current standard, with a ledger proving it.

---

## 4. Phase 1 punch list — finish the catch-up on the existing corpus

Ordered. Items marked **[blocks Phase 2]** must land before the top-up run;
everything else can run in parallel with it (Kamil's call, as agreed in docs/11).

### 4.1 Deterministic, zero-LLM

1. ✅ **DONE 2026-07-10 (this session): corpus format gate green again.**
   The overnight "Night shift" commit left 23 fim-child prompt embeds
   non-canonical across 13 families — CI's format gate was failing on main.
   Fixed with `format_corpus.exs --apply`; touched families re-validated
   (perfect + FIM-mutation gates green).
2. ✅ **DONE 2026-07-10 (this session): the `--` argument trap in the two
   paid scripts.** `mix run scripts/screen_blind_solve.exs -- --report` used to
   *silently drop* `--report` (OptionParser treats `--` as end-of-options) and
   start a real paid screen run — this actually happened during today's
   investigation ($0.67, one call; the resulting 022_003 GREEN ledger entry is
   valid data and kept). Both `screen_blind_solve.exs` and `triage_screen.exs`
   now strip a leading `--` like `resync_tfim_embeds.exs` already did.
3. ✅ DONE 2026-07-10: retro per-function + `init/1` mutation sweep.
   `validate.exs --per-fn-mutants` added (report-only, works with `--only`);
   `mutation.ex`'s `init/1` exemption is now Plug-conditional and per-file for
   bundles (a GenServer's `init/1` gets gutted; a Plug's stays intact because
   Plug.Builder invokes it at compile time); the loop and the sweep share one
   skip set via the new `Mutation.per_fn_targets/1`. **Corpus-wide result:
   297 tasks, 1,612 evals, 1,612 killed — ZERO survivors**, including all
   144 non-Plug `init/1` callbacks CI had never checked. Verified non-vacuous
   by positive control (a planted untested function is flagged SURVIVOR).
   Populations #1 and #2 close with an EMPTY remediation list — per-function
   coverage was already complete; the gap was in verification, not in the
   harnesses. Phase 2 is no longer blocked by this item.
4. **[blocks Phase 2] Leaked-chatter sweep + fix the three golds found by
   fresh-eyes review.** Deterministic grep for repair/chain-of-thought markers
   (`✅`, `🔑`, `# FIX`, `# Fixed:`, `Wait,`, `BUT since`, "the evaluator",
   emoji generally) over all gold `solution.ex`/`test_harness.exs`, then hand
   review of hits. Known confirmed cases to fix regardless:
   - ✅ DONE 2026-07-10: `001_004_penalty_escalation_01` — redesigned on the
     stable-API reading of prompt line 18: each key now stores the `window_ms`
     of its last check (internal field, no API change), and `:cleanup` removes
     ONLY keys that are indistinguishable from never-seen (timestamps expired
     against their own window, strikes fully decayed — computed to decide, not
     to mutate — and cooldown elapsed). The `ts > now` bug and all leaked
     chatter are gone. Harness: the vacuous refute replaced by observable
     negative-guarantee tests (cleanup must not reset in-window allowances,
     active cooldowns, or undecayed strike counts) — verified DISCRIMINATING:
     the old buggy gold fails exactly the new in-window test. Cascade: 4 FIM
     golds re-sliced + embeds regenerated (also fixed pre-existing @doc-drift
     conventions), _03/_05 prose updated to the new contract, wt_ copies +
     embed refreshed, tfim _04 gold reworded, 10 tfim embeds resynced. All
     gates green; blind re-screen GREEN (13/13) against the new harness.
   - ✅ DONE 2026-07-10: `020_001_file_upload_with_validation_01` — Kamil chose
     REBUILD over re-spec (prompt stayed byte-identical). Gold now genuinely
     enforces the limit via `Plug.Parsers` (rescued `RequestTooLargeError` →
     the promised 413 JSON with `max_bytes`); harness drives real multipart
     bodies through the router, asserts `max_bytes`, and accepts both
     legitimate 413 styles (in-route rescue AND `Plug.ErrorHandler`, whose
     send-then-reraise is otherwise invisible under `Plug.Test`). A hidden
     requirement (name-keyed `child_spec/1`) was removed from the store test.
     Cascade: tfim _09 gold + all 10 embeds resynced, wt_ copies refreshed,
     _02–_04 embedded-router regions updated — which surfaced pre-existing
     embed drift (a phantom `Store.max_bytes/0` in all three), also fixed (see
     §5.1 item 8). Verified: every family gate green, and a fresh blind
     re-screen GREEN. (The first re-screen was RED and correctly caught both
     harness defects — the screen doing its job.)
   - ✅ DONE 2026-07-10: `001_002_fixed_window_counter_01` — cleanup test
     rewritten to the observable-contract pattern of sibling commit 5f29311;
     wt_ harness refreshed as byte-copy; 10 tfim embeds resynced; zero
     `:sys.get_state` remains in the family; scoped gates green. The chatter
     sweep half of this item also ran corpus-wide: genuine chatter found and
     reworded in 4 families (007_002, 012_004, and — via a widened marker
     pass — 032_002 and 002_001); deliberate unicode payloads and two benign
     false positives documented and left alone.
5. ✅ DONE 2026-07-10: both stray fence artifacts removed
   (`001_001_rate_limiter_02/prompt.md:142` and `_03/prompt.md:153`); zero
   remain corpus-wide.
6. ✅ DONE 2026-07-10: all 23 bundle-parent tfim golds (016_001×10,
   021_001×10, 102_001×3) re-gated with `asserting_block?/1` — 0 failures,
   nothing to re-mint.
7. ✅ DONE 2026-07-10: `scripts/audit_repairs.exs` (one-shot; delete at the
   line per §7.2) audited 581 chains — 54 multi-attempt + 9 FIM skipped; 6
   chains changed test counts and ALL added tests; **0 flagged**. Caveat:
   `reset_attempts` wipes a chain's history on re-run, so only retained
   cycles are auditable — the clean result covers what evidence exists.
8. ✅ DONE 2026-07-10: re-measured the 7 rewritten-harness families + the 4
   unmeasured ones (ledger 618→629 rows). Latest-per-task, wt_ dropped:
   corpus mean 0.747 / median 0.769; **the tail is 20 families <0.5** (not
   19 — the prior figure predates this ledger snapshot) and 69 <0.6. The
   re-measure moved nothing in or out: the 7 rewrites reproduced identical
   kill-rates, and the 4 new families all landed ≥0.5. The <0.5 tier is
   therefore real weakness, not stale-measurement noise — input to §4.2.3.
   **Confirmed 2026-07-13** (docs/13 §1.4): this 20-family figure is the
   correct one. The `strengthen_harnesses` run attempted all 20 — 3 strengthened
   past the floor, 17 rejected (12 of them by the blind gate: their PROMPTS are
   too terse to justify any tightening test). Note the `wt_` rows in
   `logs/semantic_mutants.jsonl` are stale by design (this sweep dropped them);
   they are byte-copies of their parents and must never be measured separately —
   a tool that trusted them invented 10 phantom work items.
9. ✅ DONE 2026-07-10: benchmark decontamination check.
   `scripts/fetch_benchmarks.exs` normalizes 786 rows (MultiPL-E
   humaneval-elixir 161 + mbpp-elixir 397, McEval Elixir 50, Exercism Elixir
   178) into `test/fixtures/benchmarks/benchmarks.jsonl`;
   `validate.exs --decontam` runs exact normalized full-text match + 8-gram
   overlap (Jaccard ≥ 0.5 OR ≥ 20 shared consecutive 8-grams) over all 7,716
   corpus texts. **Result: 0 exact, 0 near-miss — max Jaccard anywhere is
   0.038.** Detector proven by `--self-test` positive control (planted
   benchmark prompt flags EXACT); fixture-missing fails loudly (exit 1).
   README carries the decontamination statement. Report-only; promoting to a
   blocking gate is a §4.2-class decision.
10. ◐ STAGED 2026-07-10: systemd user units live in `scripts/systemd/`
    (`Persistent=true` timer at 03:00 + explicit PATH for the asdf shims).
    Install needs Kamil's hands (touches user machine config):
    `cp scripts/systemd/nightly-sweep.{service,timer} ~/.config/systemd/user/`
    → `systemctl --user daemon-reload` → `systemctl --user enable --now
    nightly-sweep.timer` → `loginctl enable-linger kamil`.
11. ✅ DONE 2026-07-10: both planner scripts deleted; BACKFILL_PROGRESS.md:8
    updated to `work_status.exs`; docs/09:313 marked historical;
    BACKFILL_PROGRESS.md:109 left as historical prose; no other live
    references remain.
12. ✅ DONE 2026-07-10: `dataset_stats.exs` now reports per-shape first-line
    + first-8-words histograms (shape-keyed, not dir-prefix-keyed — fim dirs
    are detected structurally). Baseline for §7.4 confirmed: tfim and wt_
    each collapse to a single opening line; ~76% of seed/variation prompts
    open "Write me".

### 4.2 Items that cost LLM tokens or need Kamil's scope decision

1. ✅ DONE 2026-07-10: 099_002/3/4 screened — all three GREEN. **S6 now
   holds for all 303 seeds** (254 green, 49 documented keeps).
2. **Spot-review of accepted tasks (docs/10 §4.4) — first tranche done.**
   Today's fresh-eyes 12-task stratified review IS the pilot: it found the
   001_004 and 020_001 defects (§4.1.4) at a 2-defects-per-12 rate,
   concentrated in the April era. Recommendation: run one more tranche of
   ~20 April-era seeds after §4.1.3/4.1.4 land (the leaked-chatter grep will
   have cleared the mechanical part; the review then targets meaning).
3. **Weak-assertion tail, tranche 2** (population #3): the 19 families below
   0.5 family-level semantic kill, using the R10 method (audit survivors, add
   discriminating tests, never weaken, cascade, re-screen). ~$50–100 estimated.
   Recommendation: do the <0.5 tier now, set the S8 floor at 0.5, revisit 0.6
   later.
4. **Prompt-monotony rewrite scope** (population #7): recommendation — do NOT
   fold into this round; make it improvement round #2 after steady state
   (§7.4), because it touches 2,700 prompts and deserves its own tool + ledger
   + screen protocol. Decide now only whether Phase 3 generation should start
   varying registers for NEW tasks (cheap template change, §5.3 item 3).
5. **`:sys.get_state` residue** (population #5): 52 harnesses, 23/26 families
   blind-screen green. Recommendation: leave as evidence-deprioritized debt
   EXCEPT the family-001 uniformity fix (§4.1.4) — but require S9 for all new
   generation (§5.1), so the debt stops growing. Revisit only if a screen or
   spot-review implicates a specific family.
6. **105_001-class timing harnesses** (July-era regression: no fake clock,
   100–300ms sleeps): fix only on flake-ledger evidence (the R9 rule), since
   rewrites cascade into tfim gold blocks.

---

## 5. Hardening the generation loop (integrate BEFORE the line is drawn)

The loop currently enforces (base/variation): green + zero warnings + house
style + per-public-function raise mutation + blind solve (bases by
construction, variations via re-solve) + repair caps + test-deletion guard +
autoformat. FIM children get their own mutation gate; wt_/tfim_ mints get the
vacuous-seed gate + (tfim) an AST assertion check. That is already better than
most published pipelines — but several checks exist in the repo *without being
wired in*, and a few is-it-really-true gaps were found today.

### 5.1 [blocks Phase 3] Trivial, zero-LLM-cost wiring (one batch)

> ✅ **Items 1–7 DONE 2026-07-10** (one batch, 42 new tests, 254 passing;
> forward-only — the existing corpus is untouched). Highlights: warnings now
> gate all three derivative accept sites; the four S9 detectors run in the
> accept gate (`:sys.get_state`/`assert inspect`/exact-raise pins are HARD
> shortfalls; undocumented `:infinity`/trigger-sends are repair advisories);
> test-count floor `>= max(3, public_fn_count)`; variation-distinctness gate
> rejects duplicate public-function sets BEFORE any LLM spend; runs.jsonl now
> records provenance (model, active gates, honest `mutation` mode — wt_ no
> longer claims a mutant kill that never ran); stability confirmation
> re-grades every accept at a derived deterministic ExUnit seed (failures →
> flake ledger + reject); `mint_repairs.exs` auto-runs post-run.
> **Retro numbers** (gates are forward-only; for context): 32/303 seeds would
> violate the test floor; 63/220 accepted variations share a public-function
> set with base/sibling.
>
> ✅ **Item 8 DONE 2026-07-11.** `scripts/check_embeds.exs` covers module-FIM
> (`_0N`) and `wt_` embeds against the current parent `solution.ex` (tfim
> stays with `resync_tfim_embeds.exs`/S5). Named ignore conventions a–g plus,
> from the drift classification, i–m (markdown-table separator width, stub
> scaffold comments, gold-seam myers aliases, swallowed reflowed-`end`
> symmetry, wt_ AST+comment-identity fallback for formatter parens/alignment)
> and two checker fixes (indented example fences; wt_ single-file `<file>`
> wrapper on non-bundle parents). Verified by: planted-phantom self-test
> (both kinds), per-rule expected-dir clearing, and a full-corpus before/after
> diff with ZERO clean/reflow→drift regressions.
> **Classification of the residual drift** (64 families, one Opus reader per
> family; ledger `logs/embed_classify/recovered.jsonl` — 55 recovered from a
> killed workflow's journal + 9 re-run): 19 dirs were checker
> artifacts/conventions (now suppressed), the rest is REAL staleness. A
> claimed "@spec omission convention" (089_002) was REFUTED deterministically
> by git: all three 089 parents gained @doc+@spec in cff116d3 (07-07) after
> their children were minted (737f3806, 07-02) — @spec omission stays DRIFT.
> **Corpus verdicts 2026-07-11: 1068 clean / 46 reflow / 137 drift** (from
> 933/162/156 the same morning; 126 one-line "reflows" were gold-seam myers
> artifacts, not stale embeds — removed from the resync queue). The 137 drift
> dirs = 122 resync_embed + 12 fix_child_gold (parent redesigned at the
> target, incl. 131_003_04) + 3 wt_ one-token drifts (`^size` pins etc.)
> per-verdict in the ledger.
> **REMEDIATION DONE 2026-07-12 (overnight):** `scripts/resync_embeds.exs`
> (one-shot; delete at the line per §7.2) resynced 171 dirs — 114 fim embeds
> rebuilt via `EvalTask.Fim.build_skeleton`, 57 wt_ dirs fully refreshed
> (prompt via `WriteTest.prompt_md/2`, solution/harness byte-copies); all
> validated (57 wt_ perfect, 114 FIM reconstruct+mutant green). The 12
> redesigned-parent golds hand-fixed (5 `record()`→`record_t()` @spec
> renames, 5 re-extracted current-parent functions, 2 stale whole-module
> snapshots reshaped to their actual blanked function). Fixed along the way:
> `EvalTask.Fim.signature_stub` silently swallowed the NEXT function into
> the stub when a clause head's `do:` sits on a continuation line (caught
> live on 091_003_04 — the corrupt stub's intact clauses shadowed the raise
> mutant); mix test 254 green.
> **Final: embed check 1266 clean / 0 reflow / 0 drift, and CI now gates it**
> (self-test + `0 reflow, 0 drift` in validate.yml, beside the S5 tfim gate).
> S5 now effectively covers ALL derivative prompt embeds.


1. **Raw perfect invariants for fim/wt_/tfim_ accepts** — today the warnings
   check and style gate run only for base/variation; a FIM child or minted
   harness can be accepted with compile warnings. One cond clause per accept
   site (fim.ex:405, write_test.ex:74, test_fim.ex:122).
2. **Harness anti-pattern lint (S9) into the accept gate** — port the four
   detectors from `scripts/lint_harnesses.exs` into `quality_shortfall`, so a
   generated harness with `:sys.get_state` / undocumented internal sends /
   undocumented `:infinity` / `assert inspect(...)` / exact raise-message pins
   is repaired or rejected, not merely advised against in the prompt.
3. **Minimum test-count floor** — `tests_total >= max(3, public_fn_count)`;
   both numbers are already in every grade JSON (docs/10 §1.3, never landed).
4. **Variation-distinctness gate** — reject a variation whose public-function
   set equals the base's or an accepted sibling's, BEFORE the grading cycle
   (saves LLM cost; machinery exists in `Mutation.public_functions/1`).
5. **Acceptance provenance (S12)** — record in `runs.jsonl`: active gates
   (quality gate on/off, per-fn vs whole mutation, variation-blind on/off),
   model, and STOP hardcoding `mutant_failed: true` at wt_/tfim_ mint where no
   mutant ever ran (write_test.ex:167, test_fim.ex:382 — the docs/10 §2.4
   finding, still unfixed).
6. **Stability confirmation grade** — one extra eval of the final accepted
   files; a flaky harness currently has one chance in the loop to look green.
7. **Post-run repair minting** — run `mint_repairs.exs` automatically at the
   end of each generation run (581 captured attempt chains, only 3 repair
   tasks minted so far; it is add-only and double-verified).
8. **Embed-staleness gate for module-FIM (`_0N`) and wt_ prompts** — only tfim
   embeds have one (S5). The 020_001 rebuild (2026-07-10) found live drift in
   `_02`–`_04`: their embedded `Store` carried a phantom `max_bytes/0` that
   never existed in the gold. Extend the staleness check to these two embed
   kinds; the 001_004 fix (§4.1.4) needs the same machinery for its cascade.
   **DONE 2026-07-12** (checker + resync + CI gate; see STATUS history).

9. **(added 2026-07-12, all landed)** Three hardening fixes from the failed-push
   investigation:
   - `EvalTask.Fim.rewrite_skeleton` trims the skeleton's trailing newline —
     spliced fences are formatter-canonical at the source (218 embeds had to be
     canonicalized after the resync wrote them with a blank line before the
     closing fence).
   - `EvalTask.Runner.quiet_compile` captures ParallelCompiler stderr: mutant
     compiles are broken BY DESIGN and their unused-alias spill made the
     pre-push gate output look like corpus rot. Diagnostics are still returned
     and counted (grading unchanged).
   - Bare-`elixir` scripts prepend `_build/test` then `_build/dev`, so dev
     beams (what `mix compile` refreshes) win — a stale test beam had silently
     shadowed freshly-compiled evaluator code for two days.
   **Gate-coverage lesson:** hand-fixing a child gold and re-running only the
   embed gate is NOT enough — 2 of the 12 hand-fixed golds (034_001_03,
   089_004_04) passed the embed gate while compiling with redundant-clause
   warnings; only the perfect eval catches that. Any hand edit to a fim
   child's files must re-run the family's perfect eval, not just the embed
   check.

10. **Registry honesty rule (pattern, applied twice on 2026-07-12):** a work
    type's `missing/2` must count only units its executor can actually produce
    today. `missing(:test_fim)` delegates to the carver
    (`TestFim.mintable_candidates/2` — the phantom-326), `missing(:fim)`
    delegates to the target pool (`Fim.missing_units/2` — 13 stuck units on
    1-2-function parents). Anything the executor *could* produce after a
    design change (bundle fim, defmacro targets, describe carving) stays out
    of the count and goes on the decision queue instead — pending must mean
    "a run can win this", or the Phase 2 exit criterion is unreachable and
    runs burn tokens on guaranteed rejections.

11. **(added 2026-07-12, landed)** Bundle-fim support, both sides (Kamil's
    call: fix if the data is valuable — it is). Eval: `Fim.reconstruct_bundle/3`
    maps the marker-stripped skeleton back onto the parent's `<file>` files
    (sequential verbatim scan, exactly one holed file) and grades through the
    shared tier-A/B/repo machinery (`run_bundle_eval`, refactored out of
    `do_run_multifile`) with candidate-scoped `:fim` analysis. Gen:
    `deterministic_skeleton` builds bundle skeletons from the same stripped
    view (`module_view/1`) and replaces-or-inserts the prompt fence — the
    missing-fence `:contract` class is gone for all fim, not just bundles.
    Verified with zero LLM calls: gold candidates for all 4 pending bundle
    seeds grade perfect through the real eval subprocess; mutants of exercised
    targets are killed. Bundles are ordinary fim work from here on.

12. **(added 2026-07-12, landed)** Macro targets for fim (Kamil's call, same
    criterion). The stub/splice/mutate/kill chain was already macro-ready —
    `errored_against_mutant?` exists precisely for a gutted defmacro blowing
    up harness compilation — but both enumerators (`Mutation.all_functions/1`,
    the gen covered-targets parser) counted only def/defp, so macro targets
    were dropped as "hallucinated" and macro-heavy parents (074_x) read as
    empty pools. Both now count defmacro/defmacrop. **Ledger lesson:** a
    permanent-reject ledger is only as sound as the gate that wrote it — the
    nine 074_x rejects predated the errored-kill fix and were purged with this
    change; when a gate is repaired, audit its ledger.

13. **(added 2026-07-12, landed) Describe-carving for tfim.** Nested `test`
    blocks inside `describe` groups are carvable targets with ExUnit-style
    qualified names; skeletonize is indent-generic (byte-identical for
    top-level, proven by a corpus-wide resync dry-run), isolation keeps the
    target's describe + its scoped setup and drops sibling tests. 219 units
    unlocked across 27 seeds at zero token cost. **Staging completeness rule
    (from the same day's bundle-fim live failures):** whatever an eval needs
    to classify a task must be staged with it — the parent's manifest.exs now
    travels with every staged parent (read_triplet + tfim gate), and repair
    replies can never clobber generator-derived files (the fim skeleton is
    re-derived after every repair).

14. **(added 2026-07-12, landed) Prompt–gate alignment rule.** Every automatic
    gate criterion a generator is graded by must be STATED in its prompt.
    The variation-distinctness gate rejected on public-function-set equality
    while the prompt only listed existing variation names — the model
    converged on the base's natural API every pass (034_001's three slots,
    also 098_003, 101_002). `Prompts.variations` now lists every taken set as
    a hard constraint. Corollary on tracking repeat failures: permanent
    skip-ledgers are reserved for DETERMINISTIC verdicts; stochastic
    (LLM-quality) failures get their systematic cause fixed, then repeat
    offenders go to a human triage list — never an automatic permanent skip
    (see item 12's ledger lesson for why).

### 5.2 Worth one LLM call per task (decide before Phase 3)

1. **Accept-time blind screen for new BASES.** Today's base flow is blind on
   attempt 1, but a base accepted after repairs was solved by a fixer who SAW
   the harness — acceptance-after-repair proves nothing about prompt
   sufficiency, and nothing re-solves the final prompt blind. Rule that
   captures the value cheaply: any base accepted with `attempts > 1` gets one
   independent blind re-solve appended to the screen ledger; red → quarantine
   for triage instead of promotion. (Variations already have this via the
   R4b in-loop blind solve.)
2. **Entailment judge on repaired accepts** — the triage-judge prompt ("quote
   the prompt sentence that entails this assertion — or say none") applied to
   the diff of harness changes made during repair. Catches assertions bent
   toward the harness during fixes; human sign-off stays mandatory for prompt
   edits.

### 5.3 Template upgrades (free, forward-only — do with Phase 3, not before)

1. Harness checklist in the prompt templates: ≥1 negative/error-path test per
   public function, boundary tests, `describe` grouping, OTP conventions
   (`@impl true`, non-blocking `init/1`, `handle_info` catch-all) — docs/10
   §3.4, never landed. Share ONE harness-rule constant between base/variation/
   write-test templates (they are currently triplicated and have already
   drifted once).
2. Request doctests and (where apt) one property test — zero exist corpus-wide,
   and 26 golds carry `iex>` examples that are never executed.
3. Rotate the few-shot exemplar (still the single compile-time rate-limiter
   triplet — the root cause of the GenServer + "Write me" monoculture) across
   3–5 solved tasks of different shapes; add named style axes to the variation
   template. Also fix `fim_select`'s "prefer private helpers" line (the gate
   then rejects them as inconclusive).
4. **Serialization spec for training export** (from external research §6):
   write the per-shape contract — system prompt, fencing, hole-marker
   convention, one-shape-per-example — before the first training run, and a
   cheap validator that each exported example round-trips exactly one shape
   template. FIM shapes should export as natural-language infilling
   instructions for chat SFT (the chat-FIM literature), not sentinel tokens.
5. **Difficulty metadata for free**: record each seed's blind-screen outcome
   (green-first-try / green-after-fixes / triaged-keep) as a difficulty field
   in the dataset stats — the one-sample version of pass-rate difficulty
   signals used by SelfCodeAlign.

### 5.4 Explicitly deferred (documented, not forgotten)

- **Sandboxing/forgeable results** (docs/10 §2.1): fine while grading only our
  own trusted golds; becomes mandatory the day alternate-model or benchmark
  grading starts. Revisit then, not now.
- **Randomized ExUnit seed audit** (seed is pinned to 0; order-dependence bugs
  are deterministic and invisible): cheap to run as an occasional sweep
  variant; low expected yield; not wired.
- **House-style analysis upgrade** (per-function AST walk instead of
  "one `@spec` anywhere counts", per-file bundle analysis, Credo or drop the
  dep, fix the broken SQLi regex): real but low-yield polish; schedule as part
  of improvement round #2 alongside the register rewrite.

---

### 5.5 LOOP PARITY — the Phase-3 cutover contract (Kamil, 2026-07-15:
### "new data must be born at the bar we are retrofitting — no second month")

Every check the catch-up campaign ran retroactively, mapped to whether the
GENERATION ACCEPT PATH enforces it today. **Phase 3 does not start until every
row reads ENFORCED, or Kamil explicitly waives it in this table.** The final
safety net is the cutover acceptance test at the bottom.

| # | check class (origin) | at accept TODAY | carrier to close |
|---|---|---|---|
| 1 | compile + green + 0 warnings + perfect raw invariants | ENFORCED (Cycle/Evaluator) | — |
| 2 | canonical format | ENFORCED (autoformat) | — |
| 3 | whole-module + per-function raise mutants | ENFORCED | — |
| 4 | FIM mutation gate | ENFORCED | — |
| 5 | flake filter / stability confirmation | ENFORCED | — |
| 6 | S9 harness anti-patterns (reach-ins, `assert inspect`, exact messages, sleeps, min tests) | ENFORCED (ported into `Evaluator.quality_shortfall`) | — |
| 7 | temp-path collision rule (`System.pid()` — the 102_002 flake class) | ENFORCED at accept (2026-07-15, `quality_shortfall`) | — |
| 8 | S6 blind solve, variations | ENFORCED (R4b in-loop) | — |
| 9 | S6 blind solve, attempt-1 bases | ENFORCED by construction (Step B never sees the harness) | — |
| 10 | S6 blind RE-screen, repaired bases (6/22 shipped gaps) | ENFORCED (default-ON 2026-07-15, Kamil: quality gates are never optional; covers repaired VARIATIONS too — F17-9; `GEN_BLIND_RESCREEN=0` is a debugging override only) | — |
| 11 | entailment judge on repair-time harness DIFFS (§5.2.2) | **partially covered**: the default-ON re-screen (row 10) + promise audit (row 13) close most of the window; a dedicated diff judge remains unbuilt | build only if post-cutover audits show residual leakage |
| 12 | semantic-mutant kill FLOOR (S8) | ENFORCED (default floor **0.6** since 2026-07-15 — rejects the measured corpus tail of 68 families < 0.6; `GEN_SEMANTIC_FLOOR` overrides the number, `=off` disables for debugging) | Kamil may tune the number |
| 13 | promise-coverage (T2.2's dominant class: ~74 gaps + F10 — documented options/defaults/modes never exercised) | ENFORCED (default-ON 2026-07-15: `GEN_PROMISE_AUDIT` promise audit on roots — add-only bite-proven tests, close_gaps' flow in-loop; first production outing grew the base 12→17 tests; docs/17 §5–6) | T1.4's checklist still raises what gets AUTHORED |
| 14 | gold/prompt semantic defects on PASSING tasks (12 gold + 3 prompt in the 60-root batch) | ENFORCED for observable defects (default-ON promise audit: an anchored test that FAILS vs the gold machine-proves the defect and forces a repair — proven live on its first outing: the F17-1 timer-leak class caught and repaired at accept time, docs/17 §6) | the periodic `rubric_judge`/`semantic_review` cadence over NEW accepts remains the backstop for unobservable/prompt-side defects — see acceptance test below |
| 15 | @spec truth (019_001/038_001 class) | **MISSING** | T1.6 Dialyzer (one mix.exs change, Kamil) |
| 16 | @doc prose claims vs behavior (F12 class: "cancels any pending check" that doesn't) | **MISSING** | T1.4 checklist item + rows 13/14's instruments |
| 17 | degenerate-input robustness (duplicate list entries, match-spec-significant atoms, cancel_timer races — T2.4-T's three) | **NOT enforced** | T1.4 edge-case clause in templates + row 14 cadence |
| 18 | derived-shape gates (wt inherit-confirm, tfim isolation-kill, bugfix six-property, adapt RED gate) | ENFORCED in the minters | — |
| 19 | embeds regenerable (invariant 3, all five child kinds) | ENFORCED at mint + CI/pre-push drift gates; all four gates self-test in CI (2026-07-15) | — |
| 20 | variation distinctness | ENFORCED | — |
| 21 | prompt-register diversity (76% "Write me", frozen exemplar) | **MISSING** | T1.4 template/exemplar rotation |

**The cutover acceptance test (the backstop for everything a gate can't
prove):** the FIRST Phase-3 batch (~20 bases + their derivatives) is run,
before the throttle opens, through the SAME instruments that found this
month's debt — full `semantic_review` on every new root, a `rubric_judge`
two-family pass, the perfect/mutant/embed/format sweeps, and the export
round-trip. Requirement: ZERO triage-grade findings (both-family lows or
confirmed review findings). Any finding = stop, fix the GENERATOR (not the
data), regenerate, re-run. Only then does Phase 3 continue — that is the
moment "the loop produces at the retrofitted bar" stops being a claim and
becomes a measurement.

## 6. What the external survey added (sources in the research notes)

Ranked deltas this repo does not have; 1–3 and 5 are folded into §4/§5 above:

1. **Decontamination against public Elixir benchmarks** (§4.1.9) — Elixir IS in
   MultiPL-E (humaneval-elixir, mbpp-elixir) and McEval; the standard
   mitigation is 8/10-gram overlap plus exact match over prompts AND solutions
   (Tülu 3, Qwen2.5-Coder, StarCoder2 recipes).
2. **Per-shape serialization spec** before training (§5.3.4) — chat-template
   mismatch and shape-mixing are documented failure modes; FIM-in-chat needs
   the instruction-style framing.
3. **Register-diversity measurement + variation** (§4.1.12, §7.4) — frozen
   instruction templates are a documented cause of prompt-form overfitting.
4. **Rubric LLM-judge pass over PASSING tasks** — OpenCodeInstruct's ablation
   shows judge filtering adds measurable quality beyond execution filtering
   (their 3-axis rubric: requirement conformance, logical correctness,
   edge-case consideration). Our judge only ever sees blind-solve FAILURES.
   Candidate for improvement round #2 as a sampled report — pairs naturally
   with the spot-review (§4.2.2). A second judge from a different model family
   on a sample, with agreement logged, guards against single-judge bias (PoLL).
5. **Difficulty metadata from existing ledgers** (§5.3.5) — near-free.
6. Validation that our mutation stack is ahead of published dataset pipelines —
   no major dataset paper reports mutation scores at all; semantic-mutant kill
   rate is exactly the "false-positive rate of the test oracle" metric the
   HardTests line of work argues matters. Promoting S8 from report to floor is
   justified once the tail is fixed.

---

## 7. Drawing the line: steady state and the improvement-round protocol

### 7.1 Definition of the line

The line is drawn when ALL of these are true:

1. §4.1 items marked [blocks Phase 2] + §4.2.1 are done (existing corpus meets
   Standard v1 everywhere it deterministically can).
2. Phase 2 top-up ran to completion: `work_status.exs` shows **0 pending
   units of every work type** — variations, FIM, write-test, test-FIM.
3. §5.1 is merged (the loop enforces the standard by itself), and the §5.2
   decision is made.
4. Phase 3 has resumed and its first batch validated clean under the full gate
   suite — proving the ONE command is sufficient with no post-processing.

At that moment: flip `/STATUS.md` to STEADY STATE and execute §7.2.

### 7.2 What gets deleted at the line (and what deliberately survives)

**Delete — job finished:**

| Item | Precondition already met? | Notes |
|------|---------------------------|-------|
| `scripts/backfill_plan.exs`, `scripts/backfill_status.exs` | yes — superseded by `work_status.exs` | can go now (§4.1.11), no need to wait |
| `BACKFILL_PROGRESS.md` | after Phase 2 | it is the July-2 run's ledger; archive in git history |
| `scripts/lint_harnesses.exs` | after §5.1.2 ports its detectors into the accept gate | its one-shot `--fix-prompts` backfill is long applied |
| `scripts/screen_blind_solve.exs` + `scripts/triage_screen.exs` | after §5.2.1 puts screening into the loop AND a CI check flags any edited `_01` prompt whose sha lacks a green/keep ledger entry | ledgers (`logs/screen_blind.jsonl`, `screen_triage.jsonl`, `screen_candidates/`) are kept as audit data forever |
| The word "backfill" from the codebase | after Phase 2 | remove `GEN_ONLY=backfill` / `GEN_SKIP_BACKFILL` and the two-work-list vocabulary from cli.ex/config.ex/catalog.ex, work_status footer, README, tests. Touch-list documented in the script-inventory research notes |

**Keep forever — easy to mistake for catch-up tooling:**

- `resync_tfim_embeds.exs` — its dry run IS the CI staleness gate (S5).
- `work_status.exs` + the `GenTask.Work` registry — this is the loop's
  convergence core, not a backfill tool: it is what makes an interrupted run
  resumable ("perform exactly the missing units"). After the line, the plain
  run naturally computes an empty top-up list and proceeds to new ideas; the
  *mechanism* must survive even though the *vocabulary* goes.
- `mint_repairs.exs` — consumes every future run's attempt chains.
- `run_detached.sh`, `nightly_sweep.sh`, validate/format/eval/run_all/
  dataset_stats/generate — permanent core.

### 7.3 The improvement-round protocol (how ALL future upgrades work)

Whenever we want to raise the standard after steady state (new gate, new style
rule, new shape), the flow is always the same six steps — this is the answer to
"it must always be obvious whether we are catching up or producing":

1. **Flip `/STATUS.md`** to CATCHING UP with a named round and a new row in the
   history table. New-base generation pauses.
2. **Bump the standard**: add the requirement to §3's checklist as S-next,
   with a version bump (Standard v2, v3, …).
3. **Wire the check into the loop + CI FIRST**, so every task generated from
   this moment already meets the new standard. (This ordering is what prevents
   the era-stratification of §2 from ever recurring.)
4. **Write a one-shot upgrade tool** for existing data, with its own ledger
   (`logs/round_<n>_<name>.jsonl`) so an interrupted run resumes and the work
   is auditable. Idempotent, add-only where possible, cascade-aware
   (parent edits regenerate children).
5. **Run to completion, then verify**: full corpus sweep against the whole
   standard (not just the new check), plus the blind re-screen of any touched
   seed prompts.
6. **Delete the tool**, keep the ledger, flip `/STATUS.md` back to STEADY
   STATE, record the round as done in the history table.

### 7.4 Already-queued future rounds (do NOT start before steady state)

- **Round #2 — prompt-register diversity**: rewrite passes over the 2,396 tfim
  + 302 wt_ single-template prompts and the "Write me" seed register; needs
  §4.1.12's metric for before/after, its own tool + ledger per §7.3, and a
  blind re-screen budget. Pairs with the house-style analysis upgrade and a
  sampled rubric-judge pass (§6.4).
- **Round #3 (candidate) — new shape families** from docs/07 §4 (de-doc pairs,
  explain pairs, mutant-repair tasks): each lands as one `GenTask.Work`
  registry entry + runner, which the loop and `work_status.exs` pick up
  automatically — the registry design was built for exactly this.

---

## 8. Snapshot 2026-07-10 (for future diffing)

- Corpus: 3,858 dirs = 83 originals + 220 variations (303 seeds) + 854 FIM +
  302 wt_ + 2,396 tfim_ + 3 repair_. ~12.4M estimated tokens, 81.8% prompt text.
- Pending work: 490 new bases queued; top-up = 11 variation seeds (+29 units),
  25 FIM seeds (+57), 103 tfim seeds (+624), write-test complete.
- Screen ledger: 300/303 seeds screened — 251 green, 49 triaged keeps;
  unscreened: 099_002/3/4. Triage: 0 open prompt gaps.
- Semantic mutants: mean 0.740 / median 0.769 task-level; family-level tail:
  19 < 0.5, 68 < 0.6; 7 stale rows + 4 unmeasured families pending re-measure.
- Flake ledger: 26 entries, no unfixed repeat offender (104_004 and 625_001
  both fixed and holding); nightly sweep NOT yet scheduled anywhere.
- Gates all green on this machine after today's fixes: full-corpus validation
  3,858/3,858 perfect (2026-07-10 morning), format check 0 deviating,
  embed-staleness dry run clean, `mix test` 206 passed.
