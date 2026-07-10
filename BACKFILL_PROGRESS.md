# Backfill progress

> Running ledger for the **full backfill** of all accepted `_01` records (variations +
> FIM + write-test + test-FIM derivatives). Mechanism: the built-in generation loop
> (`scripts/generate.exs`, `GEN_ONLY=backfill`), subscription-backed `claude -p`,
> mutation-gated + self-repairing + insert-only + resumable. Started 2026-07-02.
>
> Live status any time: `mix run scripts/work_status.exs` (recomputed from disk).
> Structured per-task ledger: `logs/runs.jsonl`. Console: `logs/backfill_console.log`.

## Baseline (2026-07-02, before this run)

| metric | value |
|---|---|
| backfill seeds needing something | **125** |
| ├─ need variations (LLM) | 50 |
| ├─ need FIM top-up (LLM) | 125 |
| ├─ need write-test (deterministic) | 1 |
| └─ need test-FIM top-up (deterministic) | 9 |
| corpus `_01` dirs | 182 |
| corpus `sfim` subtasks (`_02+`) | 200 |
| corpus `wt_` dirs | 181 |
| corpus `tfim_` dirs | 519 |

`fim_max_per_task=3`, `tfim_max_per_task=3`.

Projected additions at full completion: ~150 variation triplets (50×3), FIM top-ups
bringing every `_01` to 3 subtasks, +1 wt, +tfim top-ups — plus derivatives chained
onto each newly-accepted variation (each new variation `_01` itself gets FIM/wt/tfim).

## Plan / phases

- [x] **Phase 0 — deterministic backfill** (`GEN_SKIP_VARIATIONS=1 GEN_SKIP_FIM=1`): DONE. Created 0 new dirs — all remaining deterministic "needs" were un-fulfillable edge cases (1 Postgres + 8 describe-nested). Corpus wt/tfim already complete. Ran the vacuous-harness self-check over all 125 seeds.
- [ ] **Phase 1 — full LLM backfill** (`GEN_ONLY=backfill`): RUNNING (`logs/backfill_console.log`). variations(50) + FIM(125) + chained derivatives. Hours, subscription-backed, background.
- [ ] **Phase 2 — corpus verification**: `scripts/validate.exs` (every reference green + every FIM target mutation-killed) + spot-review of generated tasks for sensibility/house-style + `dataset_stats.exs`.

## Checkpoint log

_(newest last; each entry = a supervised checkpoint with counts + verification notes)_

### C0 — baseline captured
`REMAINING seeds=125 vars=50 fim=125 wt=1 tfim=9 | CORPUS _01=182 sfim=200 wt_=181 tfim_=519`

### C1 — Phase 0 running + findings
- Deterministic backfill in progress (`logs/backfill_det_console.log`), no `claude` calls.
- **Finding A (fixed):** `017_001` is the only Postgres-tier seed (`manifest.exs %{db: :postgres}`).
  Its wt/tfim grade `skipped` → never promoted → `needs_write_test?`/`needs_test_fim?` stayed
  true forever, re-attempted each run + polluting `logs/errors/`. `docs/06` §6 specified a
  `gradable_skip?` guard that `catalog.ex` never implemented. **Applied** the guard (+ unit test);
  Postgres-tier seeds are now excluded from wtest/tfim backfill (variations/FIM still allowed, since
  a variation is a fresh triplet that may grade under SQLite). To compile + test after Phase 0.
- **Finding B (to review in Phase 2):** the per-seed vacuous-harness self-check is flagging
  harnesses that don't kill a raise-mutant of some public fn — e.g.
  `010_003_exclusive_lease_manager`: `__default_clock__/0` not exercised. Likely benign
  (injected-clock default accessor), but collecting all such warnings for batch review.

### C2 — Phase 0 complete, Phase 1 launched
- Phase 0 (`GEN_ONLY=backfill GEN_SKIP_VARIATIONS=1 GEN_SKIP_FIM=1`) exit 0. **0 new dirs** (git-clean `tasks/`).
- Corrected counts after the `gradable_skip?` fix (compiled; 22/22 catalog tests green):
  `REMAINING seeds=125 vars=50 fim=125 wt=0 tfim=8 | CORPUS _01=182 sfim=200 wt_=181 tfim_=519`
- **Finding C:** the 8 remaining `needs-tfim` seeds (018/019/037/072/074/075/087/096) have **0
  top-level `test` blocks** — all `describe`-nested. `TestFim` v1 carves only top-level `test`
  (docs/06 §11.1 deferral), so they produce nothing (cheaply). Not a bug; would need indent-aware
  `describe` carving to unlock (~24 potential tfim). Left as documented deferral.
- **Finding A confirmed live:** Phase 0's OLD code re-attempted `017_001` tfim **23×** (all rejected,
  same `_02` slot → never recorded → repeats every run). The fix eliminates this. Removed the 2
  orphaned `017` error logs + a stale `erl_crash.dump`.
- **Carry-over:** `logs/errors/` has 4 prior `095_*` money-module FIM failures — to inspect during
  Phase 1 (FIM top-up will re-attempt them).
- Phase 1 launched: `GEN_ONLY=backfill mix run scripts/generate.exs` (bg). Health-check next.

### C3 — Phase 1 healthy, early spot-verifications green
- ~6/125 seeds, 5 FIM top-ups accepted (all `_04`, first attempt, mutant killed) across families
  (rate-limiter, fixed-window, leaky-bucket, GCRA, interval-scheduler). No errors/stalls.
- Independent re-grades in fresh BEAMs: `001_001_rate_limiter_04` → fim/10-10/**1.0**;
  `003_001_leaky_bucket_..._04` → fim/19-19/**1.0** (a `defp refill/4` target — private-fn FIM works).
- 30-min heartbeat monitor active (`seeds/125 accepted rejected item_errors usage_pauses`).

### C4 — subscription usage-window pause (expected)
- Progressed to **seed 45/125** (through `015_001`, last successful call `015_001_heartbeat_monitor_fim03`),
  **118 FIM derivatives accepted / 4 rejected** (2 coverage, 1 `:contract`, 1 compile — all handled),
  **0 errors**, then hit the **5-hour subscription usage window** (~2026-07-02 22:15 UTC).
- Loop is auto-riding it out: sleeps 15 min/attempt, retries indefinitely up to a 6h cap
  (`GEN_USAGE_MAX_WAIT_MS`), resumes automatically when the window resets. No data lost.
- Variations (50 bases, `016_001`+) had NOT started yet — they begin right where the pause hit.
- Monitor switched to **change/exit-only** (quiet during the pause; pings on resume or finish).
- Realistic timeline now spans multiple usage windows (likely into 2026-07-03+). Fully resumable:
  re-running `GEN_ONLY=backfill mix run scripts/generate.exs` picks up exactly where it left off.

### C5 — resumed; variations landing + verified
- Window reset ~2026-07-03 01:xx UTC; loop resumed automatically (no data lost, `usage_pauses` steady at 10).
- **Variations started** (`016_001`+): `016_002/003/004` + `017_002/003/004` all ACCEPTED (2 attempts
  each = one repair then green + mutant killed). At seed 49/125, accepted=154, variations=6.
- **Key decision validated:** `017_*` (variations of the Postgres-tier `017_001`) grade GREEN — a
  variation is a fresh triplet with no Postgres manifest, so it grades under SQLite. Confirms *not*
  excluding variations for gradable-skip seeds was correct.
- Independent re-grades (fresh BEAM): `016_002` → single/9-9/**1.0**; `017_002` → single/12-12/**0.97**
  (minor analysis point; green + accepted). 4 total re-grades now, all correct. Note the model made
  the Phoenix-variation problems **single-file** (cleaner than multifile).
- **Finding D (Phase 2):** FIM on **multifile** parents fails — `016_001`'s 3 FIM candidates all
  `REJECTED (:contract)` (model can't emit the single-function reply for a `<file>` bundle). Likely
  systemic for the ~10 Phoenix multifile `_01`s → they get variations but ~no sfim. Handled (rejected,
  loop continues); flag as a known limitation / possible prompt fix.

### C6 — Finding A correction (fix was incomplete) + rejection spike explained
- Rejected jumped 7→33 in one seed: **23 benign `tfim_017_001` rejects** ("reconstruct not green")
  + a few multifile FIM `:contract`. `item_errors=0` — nothing bad promoted.
- **My `catalog.ex` `gradable_skip?` fix was INCOMPLETE.** It corrects the `needs_write_test?`/
  `needs_test_fim?` flags (so `backfill_status` is right), but `cli.ex:run_backfill_item` derives
  wt/tfim for `self_seed` **unconditionally** (never reads those flags), so `017_001` STILL wastes
  23 tfim + 1 wt attempt per run. The current run already passed `017_001` (variations minted OK),
  so it won't recur this pass — only on a future re-run.
- **Complete fix (apply in Phase 2, needs recompile):** in `run_backfill_item`, gate the self-seed
  in the wt/tfim derive lists by `seed.needs_write_test?` / `seed.needs_test_fim?` (variations always
  included; parent only when it still needs them). Deferred to avoid recompiling `gen_task` under the
  live loop.
- Now at seed 50/125 (`018_001`), accepted=175 (6 variations). Multifile Phoenix seeds (018–025)
  continue the pattern: variations accept (as single-file), FIM `:contract`, tfim describe-nested→none.

### C7 — deep verification during 2nd usage-window pause (seed 52 `020_001`)
- Hit the usage window again at seed 52 (`usage_pauses` 10→13). Used the idle time for **deterministic**
  verification only (no LLM agents — they'd compete for the same throttled subscription).
- Accepted so far: **160 fim + 27 tfim + 11 wtest + 11 variations = 209**; `item_errors=0`.
- **33 independent re-grades in fresh BEAMs, ALL green** across every derived shape + ~15 families,
  incl. variation-chained FIM:
  - 12 variations → single, green, 10× 1.0 + 2× 0.97 (minor line-length; tests all pass).
  - 6 tfim → test_fim, green (1.0 / one 0.93).  5 wtest → write_test, green (1.0 / one 0.97).
  - 9 fim (family-spread) → green (1.0 / 0.99 / 0.9).  ⇒ the loop's ACCEPTED verdicts are faithful.
- Variation quality (inspection): genuinely distinct problems (keyset vs faceted vs relevance search;
  trash-purge vs optimistic-concurrency soft-delete; dependency-order vs upsert-conflict bulk-create).
  `018_003` correctly **rejected** (vacuous harness — mutation gate). `grade_sample.exs` added as a tool.
- **Investigations (both benign):**
  - `095_*` logs/errors = coverage rejects (raise-mutant of `split/2` survives → uncovered → recorded
    to `fim_rejected.jsonl`; won't re-select). Not a defect.
  - multifile-FIM `:contract` = model can't emit single-fn reply for a `<file>` bundle. Bounded to
    ~10 Phoenix tasks' sfim (they still get variations+wt). Pre-existing limitation → follow-up fix.
- **Finding A complete-fix draft (apply+test in Phase 2):** in `cli.ex:run_backfill_item`
  `wt_derived = variation_seeds ++ if(self_seed && seed.needs_write_test?, do: [self_seed], else: [])`
  `tfim_derived = variation_seeds ++ if(self_seed && seed.needs_test_fim?, do: [self_seed], else: [])`
  (variations always derived; parent only when it still needs it → no `017_001` re-waste on re-runs).

### C8 — Finding E: multifile ideas (16–25) missing from tasks.md catalog
- The 12 new variations are on disk + verified green, but **`tasks.md` is unmodified** so far. Cause:
  ideas **16–25 have no `### N.` base line** in `tasks.md` (they were merged from `tasks_multifile/`
  without catalog entries — 15 and 34 exist, 16–25 don't). `Variations.build_variation` calls
  `_ = Catalog.insert_variation!(...)` (result discarded), which returns `:base_not_found` and no-ops.
- **Not a universal bug:** the run has only processed variation bases 16–20 so far (all multifile). Once
  it reaches single-file bases (34, 35, …, which DO have base lines), `tasks.md` will update normally.
  `GEN_RECONCILE=1` can heal missing entries — but only where a base line exists, so it also can't
  catalog 16–25. Loop correctness is unaffected (done-detection is dir-based).
- **Phase 2 options:** (a) add `### N.` base entries for ideas 16–25 to `tasks.md` (recovered from each
  `016_001…025_001` prompt.md), then `GEN_RECONCILE=1` to catalog their variations; or (b) accept the
  gap and just reconcile the single-file variations. Recommend (a) for a consistent catalog.
- Run still paused on the 2nd usage window (seed 52); resumes automatically. Deterministic verification
  exhausted for now — holding for resume/completion, then Phase 2.

---

> **Closed (2026-07-09).** The backfill completed; the corpus then went through the full
> QA-audit campaign — blind-solve screen, prompt/harness backfills, mutation + format +
> flake gates, CI. This file is a historical ledger; current state and operations live in
> `docs/10-quality-assurance-audit.md` (§7 orientation) and `README.md`.
