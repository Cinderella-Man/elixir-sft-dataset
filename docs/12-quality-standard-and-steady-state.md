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
| S3 | Harness kills the raise mutant of **every public function, including GenServer `init/1`** | loop only, since 07-02 — **retro sweep missing (§4.1.3)** |
| S4 | Files are canonical `Code.format_string!` output on the pinned toolchain | loop autoformat + CI |
| S5 | Child prompts byte-match regeneration from current parents | CI + pre-push |
| S6 | Seed prompt is blind-solvable (independent solve from prompt.md alone goes green) or is a triaged, documented hard-task keep | one-off sweep + in-loop for variations — **base accept-time screen missing (§5.2)** |
| S7 | Every harness assertion is entailed by a prompt sentence | indirectly via S6 + judge triage — no direct gate |
| S8 | Semantic-mutant kill rate measured and recorded; floor TBD after tail fixed | manual sweep, report-only |
| S9 | No harness anti-patterns: `:sys.get_state`, undocumented internal messages, undocumented `:infinity` options, `assert inspect(...)`, exact exception-message pins | manual lint script — **not gated (§5.1)** |
| S10 | No leaked assistant chatter in gold files (repair commentary, chain-of-thought, emoji markers) | **nothing checks this today (§4.1.4)** |
| S11 | Prompt/solution/harness free of overlap with public Elixir benchmarks (MultiPL-E humaneval-elixir + mbpp-elixir, McEval Elixir, Exercism Elixir track) | **nothing checks this today (§4.1.9)** |
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
3. **[blocks Phase 2] Retro per-function + `init/1` mutation sweep.**
   Add `--per-fn-mutants` to `validate.exs` (machinery exists:
   `Mutation.mutate_fn/4`, `public_functions/1`) and fix the unconditional
   `init/1` exemption in `mutate/1` (`mutation.ex:92`) so whole-solution mutants
   stop blessing a gutted `init/1`. Run it corpus-wide (~600–1,200 evals, CPU
   only). Survivors become a work list: fix the harness (never weaken), then
   cascade + revalidate the family. This closes out-of-line populations #1
   and #2 — the largest "same standard for all eras" item.
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
9. **Benchmark decontamination check — new gate, no LLM.** Download the
   MultiPL-E `humaneval-elixir` (161 rows) + `mbpp-elixir` (397 rows) subsets,
   McEval's Elixir tasks, and the public Exercism Elixir track; run 8-gram
   token overlap (the Tülu-3 recipe) plus exact-match over every prompt AND
   reference solution. Report near-misses for human review; wire the check as a
   `validate.exs` mode and publish the decontamination statement in the README.
   Classic-exercise ideas (rate limiter, LRU, trie…) make idea-level overlap
   plausible; this is the one gap any downstream consumer would flag first.
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
