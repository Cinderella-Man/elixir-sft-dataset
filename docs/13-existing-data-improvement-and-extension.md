# 13 — Improving and extending EXISTING data (research + tools, 2026-07-12)

Kamil's brief: *deep investigation into all possible ideas to improve/extend
existing data, with test runs proving the tools work, and future fresh
generation covering everything we extend.*

Method: (a) deterministic corpus survey (real counts, zero LLM — the
`opportunity survey` below), (b) a 5-agent idea-mining fan-out over docs, the
generators, corpus samples, and training-value priors, adversarially critiqued
(55 raw ideas → ranked), (c) build + pilot the winners, (d) wire every new
shape through `GenTask.Work` so generation parity is automatic.

**The parity mechanism (read this first):** any shape registered in
`GenTask.Work` with `stage: :derived` is counted by `work_status`, minted by
the `generate.exs` backfill executor for EVERY seed with missing units — old
and new alike. "Future fresh data covers everything we extend" is therefore a
one-entry requirement per shape, not an ongoing discipline. Shapes that are
exporters rather than task dirs (multi-turn dialogues) are the exception and
carry an explicit loop-step note.

## 0. The opportunity survey (measured 2026-07-12, 332 roots)

| # | opportunity | measured volume |
|---|-------------|-----------------|
| 1 | killed semantic mutants (verified broken/fixed pairs) | **9,641** |
| 2 | @spec sites / @doc sites / @moduledoc | 1,869 / 1,262 / 410 |
| 3 | property blocks (StreamData) | 75 in-corpus + 29 in 075_001 alone after describe-carving |
| 4 | TDD-inverse (tests-as-prompt) | 332 roots |
| 5 | attempt chains vs minted repair dirs | 745 chains / 15 minted; 86 multi-attempt chains end accepted |
| 6 | prompt-opener monotony | 80/332 roots share one 40-char opener |
| 7 | un-carved fim targets above the 3-cap | ~2,737 |
| 8 | un-carved tfim tests above the 10-cap | ~1,900 |
| 9 | unminted rejected attempts by reason | 207 style / 60 behavior / 57 compile |

## 1. BUILT AND PROVEN (this session)

### 1.1 `:bugfix` — verified bug→fix repair pairs *(shipped, registry-live)*

**What:** for every accepted single-module `_01`, mint up to 3 debugging tasks:
prompt = the original task spec + a semantically mutated (buggy) module + the
REAL failing ExUnit report captured from the parent harness; solution = the
reference module. `lib/gen_task/bugfix.ex`.

**What it teaches / fixes:** bug localization and minimal repair from a
failing-test signal — the debugging register, which the corpus almost entirely
lacked (15 repair_ dirs). Every unit is two-sided-verified: the bug provably
fails the harness (that's where the report text comes from) and the gold
provably passes. No judge anywhere.

**Diversity guards (from the critique):** one candidate per source line,
round-robin across operator classes (comparison/literal/atom/boolean);
survivors ledgered per solution-sha in `logs/bugfix_rejected.jsonl` (§5.1.10
honesty + §5.1.12 ledger rules).

**Pilot:** seeds 001_001 + 092_001 in a scratch root — 3/3 + 3/3 minted, known
semantic-tail survivors correctly rejected+ledgered, all 6 dirs grade
`shape=bugfix` 10/10 and 17/17, zero warnings, through the real eval
subprocess. One live find: the staging dir must not carry the `bugfix_` prefix
or the eval's own shape routing grabs it.

**Volume now:** registry reads **976 pending units / 326 seeds** — all free
(no LLM), mintable by the next backfill run. **Parity:** registry entry ✓
(`GEN_SKIP_BUGFIX` opt-out); eval shape `:bugfix` rides the perfect/green
sweeps automatically, excluded from `--mutants` (identical to the parent's).

**Byte-surgical requirement (found by Kamil's accept audit, same night):**
the original mint used `semantic_mutants/2`, which reprints the module from
the AST — comments stripped, whole file reflowed — so the "buggy module"
differed from the gold on 90–300 lines and the pair taught
restore-comments-and-reformat noise alongside the fix. Bugfix now mints from
`Mutation.semantic_mutants_textual/2`: the same mutation sites applied
textually to the ORIGINAL source line (running-line + deep-line tracking for
meta-less literals; one-occurrence-per-line ambiguity guard). Every unit
differs from its gold by EXACTLY one line, asserted at promotion.

**Standing audits (both born from spot checks the gates could not perform):**
- reject side: every rejected label cross-matches the independent survivor
  measurements, and a live rebuild proves the harness passes with the bug in
  place (no failing report exists to mint from). The reject ledger keys on
  solution AND harness sha — a strengthened harness re-opens yesterday's
  survivors for minting.
- accept side: `scripts/audit_bugfix.exs` re-derives both sides of sampled
  units through the real evaluator and checks all six shape properties
  (reproducible failure, report↔failure match, gold passes, gold≡parent,
  one-line diff, spec included). 6/6 on the re-piloted units.

**Export caveat (critique):** ~3 sibling units share the parent's module text —
the export contract (§3.1) must weight or dedupe families.

### 1.2 Property-block tfim carving *(shipped)*

**What:** `TestFim.carvable_blocks/1` now carves `property "…"` blocks
(top-level and describe-nested) exactly like `test` blocks; the prompt
template's noun is parameterized (`prompt_md/3`, default byte-identical to all
3,203 shipped prompts — resync dry-run: unchanged).

**What it teaches:** property-based testing (StreamData generators,
`check all`) — a prized register no other unit exercised.

**Pilot:** 075_001 (carved ZERO before) → 29 carvable, 10 minted at cap, all
with real isolation kills, all grading 29/29 clean. **Parity:** automatic —
it IS the tfim work type; new seeds with property harnesses mint them without
any further change.

### 1.3 Repair-mint manifest fix *(shipped)*

`scripts/mint_repairs.exs` verified pairs WITHOUT the parent manifest — every
tier-B family graded both sides as compile-fail → `:unverified` (the fourth
docs/10 §5.13 site found this week). Fixed in verify AND the minted dirs now
ship the manifest (self-contained). The 85 "unverified" decompose per §0 row 9;
the behavior/compile subsets re-verify on the next mint run.

### 1.4 Semantic-floor run (2026-07-13 night) — what it actually found

`strengthen_harnesses --go` over the 30-family weak tail produced three
classes, and the classification is the deliverable:

- **10 `already_ok` — phantom work items, and the diagnosis took three passes
  (recorded because the wrong turns are the lesson).** Attempt 1: "a `wt_`-vs-
  parent artifact". Attempt 2: "the R10 harness campaign invalidated the
  ledger, so docs/12 §4.2 is quoting rotten numbers". **Both were wrong in
  part; here is the verified truth, row by row:**
    1. The `R10` campaign (commit `5f74d18a`, 2026-07-09) tightened 11 weak
       harnesses. The PARENTS were re-measured the same day and jumped above
       the floor: 075_004 `0.00 → 1.00`, 073_001 `0.17 → 0.92`, 005_003
       `0.33 → 0.67`, 037_002 `0.35 → 0.65`.
    2. The `wt_` copies were NOT re-measured (the 07-10 sweep deliberately
       dropped `wt_` rows), so their 07-08 numbers still sit in the ledger.
    3. **My tool was the broken one.** `weak_parents` took the MAX row per task
       and mapped `wt_` rows onto their parents — so a stale `wt_` 0.00 dragged
       a healthy 1.00 family back into the work list. All 10 `already_ok`
       families are exactly that. **docs/12 §4.2's "20 families < 0.5" was
       CORRECT** (parent rows, `wt_` dropped); my 30-family list was not.
  **Fixes (all landed):** measurement policy is now LATEST-row (max hides
  regressions), `wt_` rows are ignored entirely (a `wt_` dir is a byte-copy of
  its parent's module+harness — the embed gates enforce that, so a separate row
  can only ever be a stale duplicate), and `validate.exs` stamps every semantic
  row with `solution_sha` + `harness_sha` so consumers can tell a measurement
  from a memory. Rows without keys, or whose keys no longer match disk, are
  labelled STALE-UNKNOWN: they still seed the work list (a hint, not a verdict)
  and the loop re-measures live before acting. The honest tail is **20
  families**, of which last night attempted all 20: 3 applied, 17 rejected.
  **Generalized rule: a measurement ledger without a content key rots silently,
  and "take the best row" is not a policy — it is a way to hide regressions.**
- **1 `applied`** — 002_003 (0.40 → 0.68, +8 tests) through every gate
  (add-only, green, lints, whole-mutant, re-measure, blind gate), wt_ twin +
  tfim embeds propagated, family re-gated perfect+mutants.
- **6 `rejected`, and the rejections are the real finding.** One fell short of
  the floor (077_001: 0.38 → 0.42 — interval-tree boundary mutants are
  genuinely hard to kill). One wrote tests the reference itself fails
  (013_001). **Four (105_001, 074_001, 013_002, 107_002, 041_001) were caught
  by the BLIND GATE**: the strengthened harness demanded behavior the prompt
  never states, a prompt-only solver failed it, the original harness was
  restored automatically.

**Diagnosis of the blind-gate group (checked, not assumed):** the unnamed
functions in those modules are only OTP callbacks/seams — the prompts do not
lack API surface, they lack BEHAVIORAL SPECIFICITY, and they are TERSE
(013_002: 15 lines, 041_001: 14, 074_001: 18). With that much solver latitude,
any test that tightens behavior necessarily pins something unstated. **So for
these families the weak link is the PROMPT, not the harness** — the honest
remediation order is: enrich the prompt (documenting real intended behavior),
re-screen it blind, THEN re-strengthen. Harness-first would have smuggled
undocumented requirements into the corpus, which is exactly what the blind
gate exists to prevent. Rejected families carry no permanent ledger entry —
only successes skip — so they re-attempt for free after a prompt fix.

**Positive control for the diagnosis:** 097_002 (the biggest win, 0.47 → 0.84)
has a DETAILED prompt that spells out its weighted-score rules — its added
tests pinned documented behavior and sailed through the blind gate. Prompt
specificity, not harness effort, predicts strengthenability. That is the work
item for the 12 blind-gate families: **enrich the prompt → blind re-screen →
re-strengthen** (all three tools exist; rejected families re-attempt for
free). Two further rejections were the S9 lint catching the model reaching
into GenServer internals (`:sys.get_state`) to kill mutants without testing
observable behavior — the accept-gate lint protecting a different tool from a
different failure mode.

### 1.5 Earlier same-day quality tools (see STATUS backlog)

`scripts/rescreen_repaired.exs` (retro blind screen; 22 calls outstanding) and
`scripts/strengthen_harnesses.exs` (30 weak-harness families, gated
strengthening incl. the blind gate). Both dry-run verified, paid runs on go.

## 2. DESIGNED, READY TO BUILD (ranked; volumes measured)

### 2.1 Adaptation pairs — base gold + variation spec → variation gold (score 8)

Prompt = the BASE task's verified solution + the sibling VARIATION's prompt
framed as "modify this existing module to the new spec"; gold = the variation's
verified solution; gate = the variation's existing harness. **Mint gate (the
critique's key addition): only mint where the base gold grades RED under the
variation harness** — deterministic proof the delta is real work. Teaches
brownfield code modification — the dominant real-world request, absent from
every current shape (all start blank or from a skeleton). Volume: ≤249
variation roots, contingent on the RED-gate measurement. Fully deterministic
mint; registry entry `:adapt` (derived, llm?: false). Sibling-text overlap →
export weighting note.

### 2.2 Multi-turn repair dialogues exporter (score 9, **PERISHABLE**)

86 attempt chains end in acceptance after ≥2 attempts: turn 1 = task prompt,
assistant = failed attempt N (its wrongness is ground truth — grade.json),
user = the verbatim persisted repair_report, …, final = re-graded green at
export. The only multi-turn convergence data available, and **the raw material
is destroyed by future runs** (`CycleLog.reset_attempts` wipes a chain when its
id re-enters the loop). Two actions: (a) an ARCHIVAL step (copy
`logs/attempts/` snapshots before any backfill), (b) the exporter script
(deterministic; needs the §3.1 conversation format decision). NOT a tasks/
shape — parity = a standing post-run export step in the loop, documented in
docs/04.

### 2.3 `dedoc_` — docs/spec-stripped "document this module" pairs (score 8)

The registry entry already exists as a comment in `work.ex`; a prototype
(`docs/prototypes/proto_dedoc.exs`) exists. Strip `@moduledoc/@doc/@spec` →
prompt "add typespecs and documentation"; gold = the accepted module. ~331
units, zero LLM, perfect parity. **Blocked on the Dialyzer gate (2.6):** the
019_001 spec-contradicts-code find proves shipped specs can lie; wrong specs
must not become training targets.

### 2.4 Style-repair pairs + fim-chain repair pairs (mint_repairs v2)

207 green-but-house-style-rejected attempts (report says exactly what to fix:
specs/docs/warnings/columns) = "bring this working code to house style" pairs
— verifiable via the house lint flipping clean while tests stay green. The 60
behavior + 57 compile rejects extend classic repair. FIM chains (excluded "for
v1") are mintable now that fragment reconstruction is solid. All deterministic.

### 2.5 Cap lifts: tfim beyond 10 (free) and fim beyond 3 (priced)

~1,900 carvable tests above the tfim cap mint for free through existing,
proven machinery (env: `GEN_TFIM_MAX_PER_TASK`). ~2,737 fim targets above cap
cost ~2 LLM calls each under today's generator — OR zero with **deterministic
sfim** (2.7). Decision knobs, not builds; near-duplication within families is
the counterweight — decide together with the export weighting (§3.1).

### 2.6 Dialyzer gate over golds (prerequisite for 2.3)

Would have caught 019_001's `@spec` lie mechanically. One-time PLT, then a
driver staging each gold with deps. CPU-only. Also a standing weekly CI gate.

### 2.7 Deterministic sfim (LLM-free code-FIM minting)

Carve function bodies directly (the machinery exists: `build_skeleton` +
templated prompt like tfim's) instead of two LLM calls per unit — makes fim
free for Phase 3 and for the 2,737 uncapped targets. Prompt prose becomes
templated rather than model-authored; decide whether that register shift is
acceptable (tfim's prompts are already templated).

### 2.8 Smaller / later

Spec-fim (1,869 sites; AST-equality gate), file-level bundle FIM (write the
migration/schema/router; 6 bundles), TDD-inverse (tests-as-prompt; 332 — near
-duplicate golds, needs export dedup), difficulty/curriculum metadata sidecar
(deterministic from ledgers), prompt-register diversity for the 80/332 opener
monotony (LLM rewrite + mandatory blind re-screen; prompt-sha ledgers churn).

## 3. INFRASTRUCTURE PREREQUISITES (from the critique — do before training use)

### 3.1 Export contract + family-keyed split + round-trip validator (score 9)

The dataset has never been exported. Measured **91.7% within-family text
overlap** — a naive random split leaks train→val and invalidates any eval.
Required: a per-shape training-export spec (incl. the FIM-as-chat decision and
the multi-turn format), a deterministic round-trip validator (each exported
example maps back to exactly one shape template), family-keyed splits (no NNN
family straddles train/val), and family/dedup sampling weights (bugfix + tfim
siblings share large context text). CI-gateable. Blocking prerequisite for
every shape above.

### 3.2 Attempt-chain archival policy

Before any backfill run that could re-enter old ids (see 2.2): snapshot
`logs/attempts/`. Cheap cron/loop step.

## 4. Priority order (recommendation)

1. Mint the 976 `:bugfix` units (free; next backfill run does it).
2. Archive `logs/attempts/` (one cp -r; protects 2.2 forever).
3. Run the two pending quality tools (22 screen calls; 30 strengthen families).
4. Build 2.1 adaptation pairs (RED-gate measurement first — free).
5. Dialyzer gate (2.6) → then dedoc (2.3).
6. Export contract (3.1) before the first training run — and BEFORE lifting
   caps (2.5), since the weighting decision changes what extra volume is worth.
7. Multi-turn exporter (2.2) after the format decision in 3.1.
