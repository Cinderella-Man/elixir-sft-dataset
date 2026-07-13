# 14 — Handover & Work Register

**Written 2026-07-13. This file assumes you know nothing about the recent work.**
Read it top to bottom and you can take over: what the project is doing right now,
what every tool and ledger is for, what is done, what is open, what it costs, and
what will bite you if you skip a step.

Reading order for a cold start: `/STATUS.md` (one screen: current mode) → **this
file** (the register) → `docs/12` (the quality standard S1–S12 + the catch-up
plan) → `docs/13` (the data-extension research: new shapes and their evidence).
`docs/10` and `docs/11` are historical campaign logs — read only when archaeology
is needed.

---

## 0. Sixty-second orientation

The repo is a **factory that produces a verified Elixir SFT dataset**, not just a
dataset. Two halves:

- **`lib/` + `scripts/generate.exs`** — the generation loop. It creates task
  units and only keeps them if they pass hard, deterministic gates.
- **`tasks/`** — the corpus: 5,860 directories, every one of which has been
  graded green by the real evaluator.

Everything else (`scripts/*.exs`) is a **tool with a ledger**: a repeatable,
resumable job that measures, repairs, or extends the corpus and writes what it
did to `logs/*.jsonl`.

**The three invariants that make this work.** Violate them and the corpus rots
silently — every incident in §6 traces back to one of these:

1. **Every unit is machine-verified.** No judge, no vibes. If a gate cannot prove
   a unit, the unit does not ship.
2. **Prompt-only solvability (S6).** A solver reading *only* `prompt.md` must be
   able to pass the harness. A test that pins behavior the prompt never states is
   a bug in the *prompt*, not a stronger test.
3. **Derived files must be regenerable, and gates must prove they still are.**
   Any child that embeds a parent's text has a resync tool AND a standing gate.

---

## 1. Corpus inventory (measured 2026-07-13)

| shape | dirs | what it is | prompt contains | gold is |
|---|---|---|---|---|
| `NNN_00b_slug_01` (roots) | **332** | base tasks + variations | the spec | `solution.ex` |
| `NNN_00b_slug_0N` (fim) | **991** | code fill-in-the-middle | module with ONE function `# TODO` | that function |
| `wt_…` | **331** | "write the tests" | module + parent spec | the gold harness |
| `tfim_…` | **3,231** | test fill-in-the-middle | module + harness with ONE `test`/`property` blanked | that test block |
| `bugfix_…` | **959** | debugging | spec + a module with ONE bad line + the REAL failing ExUnit output | the correct module |
| `repair_…` | **16** | repair from a real failed attempt | the original request + the failed code + its report | the accepted fix |
| **total** | **5,860** | | | |

`mix run scripts/work_status.exs` prints what each work type still owes, live from
disk. It is the source of truth for "what is left to generate", not any doc.

---

## 2. The gates (what protects the corpus)

**CI (`.github/workflows/validate.yml`) — every push:**

| gate | protects against |
|---|---|
| `mix format --check-formatted` | non-canonical **lib/test** code |
| `mix compile --warnings-as-errors`, `mix test` | broken factory (296 tests) |
| `validate.exs --mutants` | a harness that passes a fully-gutted solution |
| `format_corpus.exs --check` | non-canonical **corpus** files |
| `resync_tfim_embeds.exs` (dry) | tfim prompts drifting from their parent harness |
| `resync_bugfix_embeds.exs` (dry) | bugfix prompts embedding a stale parent spec |
| `resync_embeds.exs --wt-all` (dry) | wt_ dirs drifting from their parent (module, harness, spec) |
| `check_embeds.exs` (+ `--self-test`) | fim/wt_ module fences drifting; the self-test proves the checker is not vacuous |
| weekly / manual | full `validate.exs` (perfect score) and `--fim` sweeps |

**Pre-push hook (`.githooks/pre-push`, enable with `git config core.hooksPath .githooks`):**
the same checks, scoped to touched families, plus the corpus-wide embed gates.

> **If a gate fails, the answer is never "loosen the gate".** Every gate in this
> table was added because something rotted silently without it.

---

## 3. The tools (all in `scripts/`, all ledgered, all resumable)

Everything below is safe to kill mid-run: state lives in `logs/*.jsonl`, keyed by
content sha, so a re-run resumes and never redoes finished work.

### Generation
- **`generate.exs`** — the loop. `GEN_ONLY=backfill` tops up derivatives for
  existing seeds; without it, it also creates new base tasks from `tasks/tasks.md`.
  **Always launch detached:** `scripts/run_detached.sh logs/<name>.log mix run scripts/generate.exs`.
  (`nohup … &` inside a tool call does **not** reliably survive. Use `run_detached.sh`,
  which `setsid`s.) It rides out token-limit windows by sleeping 15 min and retrying,
  forever, by design.
  Useful env: `GEN_ONLY=backfill|bases`, `GEN_EXCLUDE_SEEDS=016_001,…` (skip known
  failers), `GEN_SKIP_BUGFIX=1`, `GEN_LIMIT=N`.
- **`work_status.exs`** — what each work type still owes. `--counts` for one line.

### Verification (no LLM, free)
- **`validate.exs`** — the gate suite. Default = perfect score. `--mutants`,
  `--fim`, `--per-fn-mutants`, `--semantic-mutants` (measures assertion
  tightness), `--decontam` (benchmark overlap).
- **`audit_bugfix.exs`** — six-property audit of `bugfix_` units (bug reproduces,
  report matches, gold passes, gold ≡ parent, exactly one line differs, spec
  included). Run it on any random sample after a mint.
- **`classify_survivors.exs`** — for a below-floor family, are the surviving
  mutants **observable** (a real gap) or **internals-only** (an unreachable
  ceiling)? See §5.3 — this decides whether a family is even work.
- **`check_embeds.exs`**, **`resync_*_embeds.exs`**, **`format_corpus.exs`** — the
  drift/format gates (dry by default; `--apply` to fix).

### Improvement (LLM, costs tokens)
- **`enrich_prompts.exs`** — rewrites a too-vague `prompt.md` so it *documents the
  behavior the reference module actually implements*. Five gates: no test-name
  leak, no ≥4 verbatim module lines (a spec must not hand over the answer),
  public API preserved, strictly additive, and a **blind solve** against the
  existing harness. Cascades to `wt_` + `bugfix_` children automatically.
- **`screen_blind_solve.exs`** — the canonical S6 screen (ledger of record).
  **Run it after any prompt edit** — the ledger is keyed by prompt sha, so an
  edited prompt is "unscreened" until you do.
- **`strengthen_harnesses.exs`** — adds tests to a weak harness. Gates: add-only
  (existing test blocks must stay byte-identical — tfim golds carve them!),
  reference green, zero warnings, house/harness lints, whole-mutant killed,
  semantic re-measure ≥ floor and ≥ before, and a **blind gate**. Propagates to
  wt_/tfim children and **restores the original harness** if anything fails.
- **`rescreen_repaired.exs`** — retro blind screen of accepts that went through a
  repair loop (see §5.1).
- **`mint_repairs.exs`** — mints `repair_` units from captured attempt chains.

---

## 4. The ledgers (`logs/*.jsonl`) — what each one means

**The rule that cost us four days: a ledger row is only valid for the content it
was measured on.** Every row must carry a content key, and every consumer must
check it.

| ledger | rows | keyed by | meaning |
|---|---|---|---|
| `runs.jsonl` | 5,260 | — | every accept/reject the loop ever made (provenance) |
| `screen_blind.jsonl` | 415 | **prompt sha** | S6 verdicts. Edit a prompt → it is unscreened again |
| `screen_triage.jsonl` | 87 | task + prompt sha | human/LLM triage of S6 REDs (`entailed: true` = prompt was fine, solver was weak) |
| `semantic_mutants.jsonl` | 660 | **solution + harness sha** (since 07-13) | assertion-tightness measurements. **Rows before 07-13 have no keys — treat as STALE-UNKNOWN** |
| `strengthen_harnesses.jsonl` | 58 | harness sha (success) | one row per family per attempt |
| `enrich_prompts.jsonl` | 18 | prompt sha (success) | one row per prompt per attempt |
| `bugfix_rejected.jsonl` | 444 | **solution + harness sha** | mutants the harness cannot kill → not mintable. Strengthen the harness and they re-open automatically |
| `tfim_rejected.jsonl` / `fim_rejected.jsonl` | 21 / 1 | harness sha / — | permanently-rejected carve targets |
| `seed_verdicts.jsonl` | 487 | content sha | seed self-check (is the harness vacuous?) |
| `flaky.jsonl` | 41 | — | harnesses that needed a stability re-run |

---

## 5. THE WORK REGISTER — what is open, right now

### 5.0 Free work available immediately (no decisions, no tokens)

`work_status` currently reads **6 pending tfim units + 2 pending bugfix units**.
These appeared *because* the harness strengthening (§5.3) added tests: new tests =
new carvable tfim blocks, and a stronger harness kills mutants it previously
missed, re-opening bugfix candidates (their reject ledger is keyed by harness sha,
so this is automatic).

    GEN_ONLY=backfill scripts/run_detached.sh logs/topup.log mix run scripts/generate.exs

Cost: CPU only. Then batch-commit the new dirs and push.

### 5.1 Blocking Phase 3 — decisions only Kamil can make

| # | item | state | evidence | cost |
|---|---|---|---|---|
| 1 | **§5.2 accept-time blind screen for repaired bases** | **OPEN — the one true blocker** | A base/variation accepted after ≥1 repair had its blindness *defeated*: the fix prompt sees the failure report (test names, missing-function errors) and satisfies it. 101_002 was accepted exactly this way and shipped a harness asserting a function its prompt never mentioned. `rescreen_repaired.exs` computes the suspect population (74 of 126 accepted variations; 42 already PASS, 10 FAIL-but-triaged-entailed, **22 never screened**) | ~22 solver calls |
| 2 | **§4.2 sign-offs** (spot-review scope, prompt-monotony scope, semantic floor) | OPEN | The semantic-floor half is now *answered with evidence* (§5.3): the floor should be "kill rate among **observable** mutants", not a flat 0.5 | decision only |
| 3 | **Nightly-sweep systemd timer install** | STAGED, needs 4 commands | `scripts/systemd/nightly-sweep.service` | 5 minutes |

### 5.2 Phase 2 (derivative top-up) — **COMPLETE**

All work types read 0 pending at the end of the campaign (the 8 units in §5.0
appeared afterwards, as a *result* of strengthening). What was fixed to get there,
in case it recurs: bundle-parent fim (eval reconstructed bundles wrongly), macro
targets (`defmacro`-blind enumerators), variation distinctness (the prompt never
told the model which APIs were taken), describe-nested tfim carving, and
predicate-named targets (`\w` cannot match `?`/`!`).

### 5.3 The semantic floor (S8) — **13 of 20 families fixed; 7 classified**

The recipe that works, and the order matters:
**enrich the prompt → canonical blind re-screen → re-strengthen the harness.**

Nine of the thirteen were only strengthenable *after* enrichment. The clincher:
`001_001`'s prompt **failed** the S6 blind screen in July; enriched (22 → 109
lines) it passes, and its harness went 0.47 → 0.87.

**The 7 that remain (classify first — `mix run scripts/classify_survivors.exs`):**

- **AT CEILING — not defects, do not "fix":** `041_001` (0.45, ceiling ≈0.82),
  `041_003` (0.48, ≈0.74), `023_002` (0.47, ≈0.53). Their surviving mutants change
  only internals (ETS flags, counter seeds/steps). The only way to kill them is a
  `:sys.get_state` reach-in, which the S9 lint forbids — and that is exactly what
  every strengthening attempt tried before being rejected. **Record the ceiling and
  move on.**
- **REAL GAPS — actionable:**
  - `063_004` — the added test pins *zero-budget timeout* semantics the prompt still
    omits. → enrich that specific behavior, re-strengthen. (~4 calls)
  - `101_001` — the model tried to *modify* an existing test block; the add-only
    guard refused. Just retry. (~2 calls)
  - `013_001` — writes tests its own reference fails, three times running.
    → investigate the reference/harness before spending more calls.
  - `077_001` — reproducibly stalls at 0.42 with 15 observable survivors (interval
    tree). The hardest of the set; needs a sharper harness, not a longer prompt.

### 5.4 Data extension (docs/13) — built, and next up

**Shipped and registry-live** (mints automatically for every future seed):
`:bugfix` (959 units) and property-block tfim carving.

**Ready to build, in priority order** (full designs + measured volumes in docs/13 §2):
1. **Adaptation pairs** — base gold + variation spec → "modify this module"; gate =
   the variation's existing harness; mint only where the base gold grades RED
   against it. Teaches brownfield editing (absent from every current shape). ≤249 units.
2. **Multi-turn repair dialogues** — 86 attempt chains where every turn's wrongness
   is machine-graded. **PERISHABLE**: `logs/attempts/` is wiped when an id re-enters
   the loop. An archive exists (`logs/attempts_archive_20260712`); take another
   before any big run.
3. **Dedoc** (`@doc`/`@spec` stripped → "document this module"). Registry entry is
   already written as a comment in `lib/gen_task/work.ex`. **Blocked on a Dialyzer
   gate** — 019_001 proved shipped specs can lie, and wrong specs must not become
   training targets. Dialyzer needs `dialyxir` added to `mix.exs` (a lockfile call
   for Kamil).
4. Style-repair pairs (207 captured), cap lifts (~1,900 free tfim above the cap).

**BLOCKING PREREQUISITE before any training run:** the **export contract**
(docs/13 §3.1). Within-family text overlap is 91.7% *by construction* — a naive
random train/val split leaks and invalidates any eval. Needed: per-shape export
spec, family-keyed splits, a round-trip validator, and dedup/sampling weights.

---

## 6. Hard-won rules (each one is a scar; ignore at your peril)

1. **A ledger without a content key rots silently.** The 07-08 semantic rows
   survived a 07-09 harness campaign and misled the floor debate for four days.
   *Every* measurement row now carries `solution_sha` + `harness_sha`.
2. **"Take the best row" is not a policy — it hides regressions.** Use the
   *latest* row. And never measure a `wt_` dir separately: it is a byte-copy of its
   parent, so a separate row can only ever be a stale duplicate (this alone
   invented 10 phantom work items).
3. **Whatever an eval needs in order to classify a task must be staged with it.**
   The parent `manifest.exs` travels with every staged parent — its absence made
   tier-B families misdetect as tier-A and fail 0/N (four separate sites).
4. **Every gate criterion a generator is graded by must be stated in its prompt.**
   The distinctness gate rejected on public-API equality while the prompt only
   listed variation *names*; the warning gate said "N warnings — silence them"
   without naming them, and the fixer burned every retry guessing. Both cost days.
5. **When a gate is repaired, audit the ledger it wrote.** Nine macro targets sat
   "permanently rejected" because a broken gate could not see a macro kill.
6. **Regexes over Elixir identifiers must handle `?` and `!`.** `\w` cannot match
   them. This silently discarded every predicate-named fim target (`valid?/4`,
   `equal?/3` …) — the most idiomatic naming class in the language.
7. **A below-floor family is not automatically defective.** Classify its survivors
   first (§5.3): internals-only survivors mean it is at its ceiling, and any "fix"
   would be the internals-pinning test the S9 lint exists to reject.
8. **Never `git add -A` while a generation loop is alive** — it sweeps the loop's
   mid-run output into unrelated commits. Stage explicit paths; batch-commit loop
   output only after the run ends and the new dirs are validated.
9. **Detach long runs with `run_detached.sh`** (it `setsid`s — a bare
   `nohup … &` inside a tool call does not reliably survive). And when you wait
   for one, **poll its PID, never a pattern**:

       while kill -0 $PID 2>/dev/null; do sleep 30; done     # correct
       while pgrep -f "enrich_prompts" >/dev/null; do … done # WRONG: the wait
                                                             # loop's own command
                                                             # line contains the
                                                             # pattern, so pgrep
                                                             # matches ITSELF and
                                                             # the loop never ends

   This exact bug cost ~100 minutes of dead time on 2026-07-13: the jobs had
   finished and written their results, but two `pgrep -f` wait-loops were waiting
   on themselves, so nothing reported completion. Also: a completion callback can
   simply not arrive — check the ledger/log yourself before concluding a job is
   still running.

---

## 7. Runbooks

**Top up derivatives (free, CPU only)**

    mix run scripts/work_status.exs                 # what is owed
    GEN_ONLY=backfill scripts/run_detached.sh logs/topup.log mix run scripts/generate.exs
    # when it exits:
    elixir scripts/validate.exs --only "<touched globs>"
    elixir scripts/validate.exs --mutants --only "<touched globs>"
    elixir scripts/format_corpus.exs --check        # --apply if it deviates
    git add <explicit new dirs> && git commit && git push   # pre-push runs the gates

**Fix a weak family (the §5.3 recipe)**

    mix run scripts/classify_survivors.exs -- --only "013_001*"   # is it even work?
    mix run scripts/enrich_prompts.exs -- --go --only "013_001*"  # spec first
    mix run scripts/screen_blind_solve.exs --only "013_001*" --rescreen   # S6 ledger
    mix run scripts/strengthen_harnesses.exs -- --go              # then the harness
    # cascades + gates run inside the tools; verify with the four resync gates

**After ANY parent-prompt edit** (they all cascade):

    mix run scripts/resync_embeds.exs -- --wt-all --apply
    mix run scripts/resync_bugfix_embeds.exs -- --apply
    mix run scripts/screen_blind_solve.exs --only "<fam>*" --rescreen

**Verify a fresh bugfix mint**

    mix run scripts/audit_bugfix.exs $(ls -d tasks/bugfix_* | shuf -n 10 | sed 's|tasks/||')

---

## 8. What "done" looks like

Phase 3 (490 queued base ideas) may start once §5.1 items 1–3 are resolved. After
its first validated batch, **draw the line** (docs/12 §7.2): delete the catch-up
tooling (`resync_embeds.exs`, `rescreen_repaired.exs`, `strengthen_harnesses.exs`,
`enrich_prompts.exs`, `mint_repairs.exs` as a one-shot), delete the backfill
vocabulary, and flip `/STATUS.md` to **STEADY STATE** — one command produces new
data, every check lives inside the loop or CI, and nothing needs catching up.
