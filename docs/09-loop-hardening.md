# 09 — Loop Hardening (pre-run batch)

> **Date:** 2026-07-03
> **Status:** IMPLEMENTED + VERIFIED (140 tests green, `--warnings-as-errors` clean,
> every change smoke-tested against real corpus tasks).
> **Scope:** everything remaining from `docs/07` §9 that makes the next generation
> run correct, cheaper, and lossless — done in one batch so the loop can be started
> against Opus immediately after. Follows `docs/08` (gate fixes + attempt capture).
> Deliberately NOT included: the deterministic dataset-expansion mints (mutant-repair
> dirs, de-doc pairs, inverse pairs — docs/07 §4.3–4.5) and prompt-register
> rewriting (§5.1) — those change corpus composition and deserve their own review.

## 0. Summary of changes

| # | Change | Files |
|---|---|---|
| 1 | **Finding A complete**: gradable-skip (Postgres) seeds excluded from FIM too, and the self-seed is derived only per its needs-flags | `catalog.ex`, `cli.ex` |
| 2 | **Finding E**: base entries 16–25 added to `tasks.md` | `tasks/tasks.md` |
| 3 | **tfim cap 3 → 10** + content-hash-keyed negative cache (`tfim_rejected.jsonl`) | `config.ex`, `test_fim.ex`, `cycle_log.ex` |
| 4 | **Vacuous-seed self-check cached** (`seed_verdicts.jsonl`, content-hash keyed) | `cli.ex`, `cycle_log.ex` |
| 5 | **Config hardening**: `GEN_LIMIT` bounds backfill; `GEN_ONLY` rejects unknown values; integer envs reject junk | `config.ex`, `catalog.ex` |
| 6 | **Quality gate completed**: `lines_over_98` + `sql_injection_risk` now gate acceptance (matching the rubric) | `evaluator.ex` |
| 7 | **run_all PASS honesty** (+ `full_pass`); **dataset_stats wt pair sizing** (completion = harness) | `scripts/run_all.exs`, `scripts/dataset_stats.exs` |
| 8 | **Variation call slimmed 12×** (titles-only catalog) + **salvage** (a malformed vN no longer discards its siblings) | `prompts.ex`, `variations.ex`, `reply.ex` |
| 9 | **`scripts/mint_repairs.exs`** — the consumer for captured attempts | new script |

New/updated tests: `catalog_test.exs` (skip semantics, cap-pinned fixture),
`config_test.exs` (new), `evaluator_test.exs` (quality gate), `reply_test.exs`
(salvage). New JSONL ledgers: `tfim_rejected.jsonl`, `seed_verdicts.jsonl`.

---

## 1. Finding A, completed (gradable-skip seeds)

`docs/08` fixed the gates; this closes BACKFILL Finding A itself, and further than
drafted:

- **`catalog.ex`**: `needs_fim?` is now `not skip? and …`. Rationale: FIM subtasks
  are graded by *reconstructing against the parent harness* — for a `db: :postgres`
  seed that harness can only ever grade `skipped`, so a FIM candidate can never go
  green and each attempt burns **LLM repair calls** (generate + up to 3 repairs),
  every run, forever. wtest/tfim were already gated; FIM was the expensive hole.
- **`cli.ex`**: `run_backfill_item` used to put the self-seed into the wt/tfim
  derivation list unconditionally ("self-gating" idempotency made that harmless for
  normal seeds but re-attempted un-mintable derivatives for skip seeds every run).
  It now honors the seed's `needs_write_test?`/`needs_test_fim?` flags.

**Verified:** `017_001` (the only Postgres-tier seed) now drops out of
`backfill_seeds` entirely — it already has its 3 variations, and everything else
about it is correctly un-derivable. Waste per backfill run goes from ~24 gate
attempts + potential FIM LLM calls to **zero**. The catalog test was updated to
encode the new semantics (a skip seed keeps only `needs_variations?`).

## 2. Finding E (catalog entries 16–25)

`Catalog.insert_variation!` searches only `tasks.md`; ideas 16–25 lived only in
`tasks_external.md`, so every newly generated variation of those ideas promoted fine
but its catalog entry was **silently discarded** (`:base_not_found`). Since the
paused backfill resumes right in this range (seed 52/125 ≈ `020_001`), this would
have bitten immediately.

Fixed by mirroring the ten `### N. <name>` base entries into `tasks.md` under a
clearly-labelled section (`## Phoenix / API Base Entries (16–25)`) that states
`tasks_external.md` stays authoritative.

**Verified:** catalog parses 568 ideas (was 558); 16–25 resolve; **none** become
false "pending base" work (all ten have `_001` dirs on disk); a dry
`insert_variation(…, 16, …)` probe returns `{:ok, _}`. Recommended once after the
next run with fresh variations: `GEN_RECONCILE=1` to backfill any entries lost
before this fix.

## 3. tfim: cap 10 + negative cache

- `GEN_TFIM_MAX_PER_TASK` default **3 → 10** (docs/07 §4.1, measured headroom:
  cap-10 supports ~1,897 tfim dirs vs 579 today, before isolation-gate attrition).
  The knob still overrides.
- **Negative cache**: both tfim reject classes (reconstruct-not-green, vacuous
  block) are deterministic for fixed content — fixed eval seed (docs/08 §2),
  immutable promoted tasks — yet were re-gated on every backfill pass forever
  (multiple eval subprocesses per block). Rejects are now recorded to
  `logs/tfim_rejected.jsonl` **keyed by the SHA-256 of the parent harness**, and
  skipped on later passes. The content key means a hand-edited parent harness (e.g.
  the 020-family fix in docs/08 §2.5) automatically invalidates its stale rejects —
  a deliberate improvement over the prefix-only `fim_rejected.jsonl` pattern.

**Verified:** dry-run top-up of `076_001_trie_01` gated 7 further blocks (cap 10,
3 existing) — all accepted, ledger written only on rejects. Note for the first
real backfill run after this change: the tfim top-up will mint up to ~7 additional
tfim per parent across 193 parents — **all deterministic, zero LLM** — so expect a
long (but cheap) first pass; `GEN_TFIM_MAX_PER_TASK=3` restores the old behavior
if that's not wanted yet.

## 4. Vacuous-seed self-check cache

`warn_if_vacuous_seed` runs the full per-public-function mutation gate (one eval
subprocess per function) on **every backfill seed on every run**, purely to log a
warning. The verdict is deterministic for fixed content; it is now cached in
`logs/seed_verdicts.jsonl` keyed by `task_id` + SHA-256(solution+harness). Cache
hit → the warning (if any) is re-emitted from the record; each seed pays the gate
cost once per content version.

## 5. Config hardening

- **`GEN_LIMIT` now bounds backfill too** (docs/05 #7): at most N items per
  work-list (N bases AND N backfill seeds). Previously `GEN_LIMIT=5` could still
  fan out over 100+ backfill seeds.
- **`GEN_ONLY` is strict**: `bases`/`base`/`backfill` accepted; anything else
  (e.g. the plausible-but-wrong `GEN_ONLY=fim`) raises instead of silently meaning
  `:bases`.
- **Integer envs are strict**: `GEN_LIMIT=5x` used to silently mean 5; now raises.
  A config typo should stop the run, not quietly reshape it.

All three covered by the new `test/gen_task/config_test.exs`.

## 6. Quality gate completed

`quality_shortfall` now also gates on `lines_over_98 > 0` and
`sql_injection_risk == true` — the two rubric-scored checks it omitted, which let
an accepted reference ship with a sub-1.0 analysis score. The house-style prompt
already demanded ≤98 columns, so this only enforces what generation was already
asked for. Expect a marginal increase in style-repair calls on new tasks; the
repair report names the offense ("N line(s) over 98 columns — wrap them").

## 7. Reporting honesty (run_all, dataset_stats)

- `run_all.exs` `status_of`: PASS now requires ≥1 passed, 0 failed, 0 harness
  errors; new distinct statuses `ERROR (n harness error(s))` and `NO_TESTS_RAN`
  replace the old vacuous `PASS (0)`. The summary's `full_pass` got the same bar.
- `dataset_stats.exs`: a wt_ example's pair size is now prompt + **harness** (the
  actual completion) instead of prompt + solution (which double-counted the module
  embedded in the prompt and omitted the completion). Corpus-wide effect:
  median example size 2,632 → 2,682 tokens; context-window-fit numbers for the
  203 wt_ examples are now truthful.

## 8. Variation call: 12× cheaper + salvage

- **Titles-only catalog**: the no-repeat constraint block in every variations call
  inlined the *entire* `tasks.md` (~473 KB and growing with every accepted
  variation — a self-amplifying cost). `Prompts.catalog_titles/1` now sends only
  the `##`/`### ` heading lines: **37 KB**, same distinctness signal.
- **Salvage** (`Reply.valid_variation_slots/2`): one malformed `vN/` group used to
  discard the entire N-triplet reply. Valid groups are now built and promoted; the
  malformed slot is logged and simply topped up on a later run (count-based top-up
  semantics already handle partial batches). Zero valid groups still errors as
  before.

## 9. `scripts/mint_repairs.exs` — the attempt-capture consumer

Deterministic, no-LLM minting of repair-pair SFT tasks from `logs/attempts/`
(docs/08 §4):

- For every chain whose last attempt is `accepted` with ≥1 earlier `rejected`
  attempt, each rejected attempt N mints `tasks/repair_<id>_<NN>/`:
  `prompt.md` = original request + broken attempt-N code + its captured
  `repair_report`; `solution.ex` + `test_harness.exs` = the accepted fix.
- **Double verification before promotion** through the real evaluator: the fix must
  grade green AND the broken code must grade non-green **against the accepted
  harness** (the repair may have changed the harness, so captured grades aren't
  reused). Pairs that don't discriminate are dropped as `:unverified`.
- Add-only and idempotent (`:exists` on re-run), `--dry-run` / `--logs` / `--out`
  flags. The `repair_` prefix is glob-safe: the digit-anchored loop enumerators
  ignore it (like `wt_`/`tfim_`), and the evaluator grades it as shape `:single`
  since the triplet is self-contained.
- v1 scope: FIM-cycle attempts (no harness in the candidate) are skipped.

**Verified end-to-end:** a synthetic chain (raise-mutant of the trie as the
rejected attempt, the real reference as accepted) minted exactly one
`repair_076_001_trie_01_00`, which the evaluator grades **1.0 / shape `:single`**;
re-run reports `:exists`. Usage after (or during) a generation run:

```bash
mix run scripts/mint_repairs.exs --dry-run   # see what's mintable
mix run scripts/mint_repairs.exs             # mint into tasks/
```

## 10. What this means for running the loop

The intended sequence is now simply:

```bash
# sanity smoke (first pending idea, writes nothing, exercises claude transport):
GEN_DRY_RUN=1 GEN_LIMIT=1 GEN_SKIP_BACKFILL=1 mix run scripts/generate.exs

# the real run (resumes backfill at ~seed 52, then continues):
nohup mix run scripts/generate.exs > logs/loop_console.log 2>&1 &

# after (or during — both are add-only):
mix run scripts/mint_repairs.exs
elixir scripts/validate.exs
```

Expected new data per run, beyond the usual base/variation/FIM/wtest/tfim:
`logs/attempts/**` (every graded attempt), `tasks/repair_*` (after minting),
plus the two new ledgers reducing repeat-run cost. Remaining roadmap items live in
`docs/07` §9 Phases 2–4 (dataset-expansion mints, prompt-register diversity,
new deps/coverage).

---

## 11. Post-smoke fixes (first live run, 2026-07-03 evening)

The first real smoke run (`GEN_DRY_RUN=1 GEN_LIMIT=1 GEN_SKIP_BACKFILL=1`) surfaced
three issues, all fixed:

### 11.1 `error_max_turns` on the fix call — `--max-turns` now 2 (`GEN_MAX_TURNS`)

Observed: base generation (2 calls) fine; the *fix* call failed `error_max_turns`
on **all 5 retries** (~3.5 min wasted), because on repair-style prompts the model
routinely *attempts* a (disabled) tool call first — with `--max-turns 1` that
consumes the only turn, and a same-prompt retry mostly re-samples the same
behavior. Two changes:

- `--max-turns` is now `cfg.max_turns` (**default 2**, `GEN_MAX_TURNS`): the denied
  tool attempt is followed by the real single-shot reply, while a runaway agentic
  loop stays bounded (the original problem with 20 turns).
- The shared output contract now states explicitly: *"You have NO tools available
  in this session — reply directly with the file contents in your message."*

### 11.2 Misleading terminal verdict — real reject reason threaded through

The run printed `REJECTED (vacuous harness (mutant survived))` when the actual
history (per the captured attempt) was: **green 14/14 → quality gate: 1 compile
warning → fix call failed**. `Cycle.reason_for/1` only sees the final grade, so any
green-but-rejected cycle was labeled "vacuous harness". `Cycle.run` now returns the
specific reason (`:reason` in the result — "house style: …", "mutation gate: …",
"tests failed (12/14 passed)", "…; repair call failed") and `Base`/`Variations` put
it on the terminal line. Transport retry warnings are also labeled with the
in-flight call (`transient error (…) on fix (135_001_…) — retry 2/5 after 4000ms`).

### 11.3 Silent minutes + opaque work-list — progress lines and a self-explaining banner

Between the task header and the final verdict the console showed *nothing* while
grades, gates, and repairs ran. Now each graded attempt prints one indented line:

```
[1/1] 135_001_data_quality_scorer_01 (base) ...
    · attempt 0: green (14/14) — house style: 1 compile warning(s) — asking for a fix
    · attempt 1: green (14/14) — all gates passed
```

And the banner explains each work-list instead of printing bare counts — including
**why the run "starts at 135"**: a *new base* is pending iff its idea is in
`tasks.md` with no `tasks/NNN_001_*` dir; ideas 1–134 are done, external-catalog,
or already built, so 135 genuinely is the first pending pure idea, and backfill was
empty only because `GEN_SKIP_BACKFILL=1` was set:

```
  new bases:      1 → next: 135_001_data_quality_scorer_01
  backfill seeds: skipped (GEN_SKIP_BACKFILL=1)
```

Without the skip flag the same banner shows
`203 needing top-up → next: 001_001_rate_limiter_01, …` — note the first
non-skipped backfill pass after the cap raise will be dominated by the
deterministic tfim top-up (no LLM, but many eval subprocesses);
`GEN_TFIM_MAX_PER_TASK=3` postpones that if the LLM work should go first.

**Verified:** banner + tfim top-up exercised live via
`GEN_DRY_RUN=1 GEN_LIMIT=1 GEN_ONLY=backfill GEN_SKIP_VARIATIONS=1 GEN_SKIP_FIM=1`
(001_001 minted tfim `_05`…`_08`+ in dry-run with the new output); attempt-progress
lines exercised via `docs/prototypes/proto_attempt_capture.exs`; 140 tests green.

---

## 12. The work registry — `GenTask.Work` (one place for "what needs to happen")

Until now, the knowledge of *which derivative work exists and when it's complete*
lived in four places at once: the `needs_*` flags in `Catalog.seed/2`, the
hardcoded chain in `cli.run_backfill_item/4`, and the two read-only planner
scripts. Adding a new work type meant touching all of them.

**`lib/gen_task/work.ex` is now the single source of truth.** Each work type is
one registry entry declaring: `key`, `desc`, `llm?`, its `stage`
(`:expand` = creates new sibling seeds, e.g. variations; `:per_seed` = own driver,
e.g. fim; `:derived` = simple per-seed derivation, e.g. wtest/tfim), its
`GEN_SKIP_*` accessor, a **pure, cheap `missing(seed, cfg)`** function (units still
to produce; 0 = complete), and for `:derived` entries a `{module, fun}` runner.

Everything downstream is registry-driven:

- `Catalog.seed/2`'s `needs_*` flags are projections of `Work.missing/3`
  (`Catalog.all_seeds/1` enumerates every `_01` for status purposes);
- `cli.run_backfill_item/4` and the post-accept chain execute all `:derived`
  entries **generically** (`run_derived_works/2`) — a new deterministic work type
  needs zero cli changes;
- **`scripts/work_status.exs`** prints the live work-type × corpus matrix — the
  re-runnable "what still needs to happen on which sets?" command:

```
$ mix run scripts/work_status.exs
work type    stage     llm   applicable  complete  pending  missing units
variations   expand    yes           83        39       44            128
fim          per_seed  yes          203       123       80            205
write_test   derived   no           203       203        0              0  ✓
test_fim     derived   no           203         0      203           1451

$ mix run scripts/work_status.exs --pending   # per-seed detail
$ mix run scripts/work_status.exs --counts    # one line, for tracking over time
```

Everything stays **idempotent**: `mix run scripts/generate.exs` performs exactly
the missing units and nothing else, so status → generate → status converges.

**To add a new work type** (say, de-doc pairs): add one entry to `Work.all/0`
(`missing` = "does `dedoc_<id>` exist?", runner = `{GenTask.Dedoc, :run}`,
stage `:derived`), write the runner module, done — planner, executor, banner
counts, and `work_status.exs` all pick it up automatically. `missing/2` must stay
pure disk/config inspection; gate-expensive checks belong in the runner behind a
negative-cache ledger (the `tfim_rejected.jsonl` / `seed_verdicts.jsonl` pattern).

Covered by `test/gen_task/work_test.exs` (registry contract, top-up semantics,
gradable-skip exclusions, summary aggregation); the legacy
`backfill_plan.exs`/`backfill_status.exs` still work and now agree with the
registry by construction.

---

## 13. Defaults: catch-up first, everything opt-OUT

The plain no-flag command is now the "do absolutely everything" invocation:

```bash
mix run scripts/generate.exs
```

Three default changes make that true:

1. **Work-list order flipped — backfill runs BEFORE new bases.** Rationale: the
   run should bring the existing record up to date (apply a raised cap or a newly
   registered work type corpus-wide) before spending LLM budget on new ideas; when
   the backfill list is empty the run flows straight into new bases — "progress
   with new ones when it runs out". The banner numbers the lists in execution
   order (`1. backfill seeds / 2. new bases`).
2. **`GEN_RECONCILE` is default-ON** (opt out with `GEN_RECONCILE=0`). It is
   insert-only and idempotent, and with Finding E fixed (§2) it simply keeps
   `tasks.md` consistent with the dirs on every run; it prints only when it
   actually healed something, and is skipped in dry-run.
3. Backfill itself was already default-on; `GEN_SKIP_BACKFILL=1` /
   `GEN_ONLY=bases|backfill` remain the opt-outs.

One deliberate exception stays opt-IN: `GEN_RETRY_FAILED` — errored tasks in
`logs/errors/` are NOT retried by default, because a permanently-failing idea
would otherwise burn its full repair budget on every single run. Retry them
explicitly (`GEN_RETRY_FAILED=1`) after fixing the underlying cause, or delete
the specific `logs/errors/<id>.log`.

Note on the relationship to `work_status.exs`: the loop does NOT need it —
`generate.exs` recomputes the identical plan internally on every start (both are
views of `GenTask.Work` + `Catalog`). The status script is purely for humans to
inspect what a run *would* do, or to track convergence between runs.
