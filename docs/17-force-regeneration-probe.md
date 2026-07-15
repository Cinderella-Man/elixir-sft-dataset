# 17 — The `--force` regeneration probe (T1.9, 2026-07-15)

**Question (Kamil):** if the generation loop ran TODAY, at what quality would new
data actually be born — and which gates from the docs/12 §5.5 parity table does
the output prove are missing?

**Method:** `mix run scripts/generate.exs 15 --force` deletes family 15
(Heartbeat Monitor — deliberately chosen as the FRESHEST retrofit: F12's timer
fixes landed 2026-07-15 morning) and regenerates it from the catalog idea with
today's loop. The wipe is left uncommitted, so `git diff` against the
retrofitted family is the measurement. Every gate now prints and ledgers its
verdict (`logs/gates.jsonl`, `GenTask.GateLog`), so "which checks ran and what
they decided" is part of the record. Run: `logs/force_015.log` (started
2026-07-15 midday, pid in `logs/force_015.pid`).

**Disposition of the probe data:** the regenerated family is an INSTRUMENT, not
a product. After analysis the retrofitted family is restored
(`git checkout -- tasks tasks/tasks.md`) unless Kamil decides otherwise; the
findings become generator work items (rule 7 Task-B halves), never hand-fixes
to the probe data.

---

## 1. Base unit result (015_001_heartbeat_monitor_01) — INTERIM

Accepted on attempt 2 of 4. The one repair was cosmetic (a 98-column line,
caught by house-style check 6/17). Console trace excerpt — this is what every
future accept looks like now:

    gate [1/8] canonical formatting ... PASS — reformatted: solution.ex, test_harness.exs
    gate [2/8] compile + green + perfect raw invariants ... PASS — 12/12 tests
    check [ 1/17] zero compile warnings ... ok
      … (17 named house-style/harness-standard checks, one line each)
    gate [3/8] house style + harness standard ... PASS — 17/17 checks ran, all ok
    gate [4/8] raise-mutant coverage — applying (7 public functions) ...
      mutant [1/7] start_link/1 gutted to raise ... killed
      … (all 7 killed)
    gate [5/8] stability re-grade at ExUnit seed 900510332 ... PASS
    gate [6/8] semantic-mutant kill floor ... SKIPPED — GEN_SEMANTIC_FLOOR unset (DARK)
    gate [7/8] accept-time blind re-screen ... SKIPPED — GEN_BLIND_RESCREEN=0 (DARK)
    gate [8/8] promotion safety ... PASS — promoted

### What visibly held (parity rows 1–9)

Format, perfect raw invariants, all 17 house/S9 checks (including the
temp-path rule), per-function mutants, the flake filter — all fired and all
enforced. The repair path worked and the test-deletion guard had nothing to
object to. **Prompt quality is a different era from the old family's birth:**
the new prompt is 104 structured lines (vs 18 unstructured), documents its
determinism seam (`:infinity` intervals + a `{:check, name}` manual trigger —
the S9 "documents-or-removes" rule made constructive), and the blind Step-B
solve was green on the first grade. Rows 1–9 are honestly ENFORCED.

### Findings — each one maps to a parity row that is NOT enforced

**F17-1 (SEVERE, probe-proven): re-registration leaks the old timer chain —
the F12 class, regenerated one day after F12 was fixed.**
`handle_call({:register, …})` schedules a new tick chain unconditionally; the
prompt promises replace-semantics for an existing name, but the previous
`Process.send_after` chain is never cancelled. After one re-register the
service is checked on two overlapping chains forever. Probe
(`probe_reregister_leak.exs`, scratchpad): 9 checks/500ms before, 19 after —
ratio 2.1. All 8 gates passed because: the harness never exercises
re-registration (row 13), no judge ever reviews accepts (row 14), and the
`@doc` "replaces its configuration and resets" glosses the leak (row 16).
This single finding is the rule-0 argument in miniature: the retro fix
(F12-A) without its generator gate (F12-B/T1.4/T1.6-class) changed NOTHING
about what the loop produces.

**F17-2 (row 13, promise coverage): ≥5 documented promises with zero tests.**
The new prompt documents, and the new harness never exercises:
  1. `:name` registration ("other functions may be called with either the pid
     or the registered name") — no named-server test;
  2. the `is_function(check_func, 0)` guard — no bad-arity test;
  3. `:infinity` ⇒ "no automatic checks are EVER scheduled" — never pinned
     (all `:infinity` tests only use manual triggers);
  4. "first automatic check happens one interval after registration (not
     immediately)" and "repeat indefinitely" — the only automatic-interval
     test uses threshold 1 and can't distinguish one tick from many, nor
     immediate from delayed;
  5. re-registration replace/reset semantics — untested (this is the hole
     F17-1 walked through).
This is T2.2's dominant retro class (~74 gaps corpus-wide) reproducing at
birth, exactly as row 13 predicts while T1.4's checklist is unlanded and no
accept-time coverage judge exists.

**F17-3 (row 21, register diversity): the opener is still "Write me an
Elixir `GenServer` module called …"** — same register as 76% of the existing
seed prompts. The monoculture survives regeneration; only T1.4's exemplar
rotation touches it.

**F17-4 (T1.4(b), doctests): zero doctests / zero property tests** in a module
whose `@doc` prose is rich. Same corpus-wide zero as before.

**F17-5 (observation, not a defect): harness volume regressed vs the
retrofitted bar.** 12 tests vs the old family's 21 (after close_gaps
strengthening). The floor gate (`max(3, public_fn_count)` = 7) is far below
what the retro campaign considered adequate for this family. The floor is a
FLOOR; the retrofitted corpus average is the real bar (docs/12 rule 0).

### Dark gates demonstrated in the output

Rows 10 and 12 didn't just fail to run — the accept LOG now says so
(`SKIPPED — … DARK`). Note this accept was a repaired accept (attempts = 2),
i.e. precisely the class T1.1's blind re-screen exists for; it promoted with
no blind evidence because the flag awaits sign-off. (This particular repair
only re-wrapped a line, so the actual risk here was nil — but the LOG can now
prove that, which is the point.)

---

## 1b. File-by-file: retrofitted 015_001 (git HEAD) vs regenerated (working tree)

Same task id, same catalog idea, one day apart. `git diff -- tasks/015_001_heartbeat_monitor_01`.

### prompt.md — 18 lines → 104 lines. The loop's biggest genuine improvement.

| dimension | OLD (born ~07-05 era, enriched in catch-up) | NEW (today's loop) |
|---|---|---|
| register | "Write me an Elixir GenServer module called `Monitor`…" | IDENTICAL opener (row 21 — monoculture survives regeneration verbatim) |
| structure | one paragraph per function, no headings | titled + 5 sections (Public API / Running a check / Transitions / Manual trigger / Robustness), bulleted contracts |
| behavioral precision | prose; edge cases implied | near-formal: transition rules given as (status, count, threshold) case analysis; "exactly once per transition", consecutive-reset worked example |
| determinism seam | injected `:clock` (used only for `last_check_at` — scheduling still real timers); `{:check, name}` tagged sends implied | documented `{:check, name}` manual trigger + `:infinity` intervals — the S9 documents-or-removes rule made constructive |
| API surface | RICHER: `deregister/2`, `:pending` initial state, `status_info` map (`last_check_at`, `consecutive_failures`), `{:error, :already_registered}` duplicate rule | SIMPLER: binary `:up`/`:down`, replace-on-re-register, `:threshold`/`:notify` in opts, no deregister at all |

The precision jump is real good news: the blind Step-B solve graded green on
the first attempt, and the harness needed no prompt-side repair. The API
simplification is content variance, not a gate failure — the catalog idea
mandates neither `deregister` nor `:pending` — but it shows the loop renders
the EASIER reading of an idea when nothing pushes difficulty (T1.4(d)
difficulty metadata / template push is the lever).

### solution.ex — 292 lines → 197. Timer hygiene regressed to pre-F12 state.

The OLD module (post-F12) tracks every service's live timer ref, cancels it on
deregister AND drains the already-queued `{:check, name}` message, and replaces
the ref on every fire — with comments explaining exactly the resurrection bug
that forced it. The NEW module discards the `Process.send_after/3` ref
entirely (`schedule/2`'s return value is ignored by every caller), so nothing
can ever be cancelled; its replace-on-re-register semantics leak the previous
chain (F17-1, probe-proven 2.1× check rate). One family, one day: the retrofit
knows WHY (its comments carry the scar), the regeneration doesn't (no gate
carries the knowledge — rule 7's whole argument).

Both are house-style clean (@moduledoc/@doc/@spec everywhere, zero chatter);
the new one even adds @typedoc. Style gates cannot see semantics.

### test_harness.exs — 464 lines / 21 tests → 239 lines / 12 tests.

Techniques are comparably good — the OLD uses three named Agent helpers
(fake Clock, notification collector, controllable check fn); the NEW's
`script/1` sequenced check function is arguably cleaner. Both are S9-clean,
sleep-free (bounded `assert_receive`/`refute_receive` only), deterministic-first.

The decisive difference is the retrofit's fingerprint — the OLD harness ends
with a "Real timer-driven scheduling" section (first check only AFTER the
interval; timer re-arms so checks repeat; deregistering stops timer-driven
checks) plus stale-message and re-register-after-deregister tests. Those are
exactly the close_gaps/F12-era pins, and they are exactly the tests whose NEW
analogs are missing (F17-2 items 3–5). The one NEW automatic-timer test
(threshold 1, 20 ms interval) cannot distinguish "fires once" from "repeats",
nor "immediately" from "after one interval". A NEW-harness analog of the OLD
timer trio would have caught F17-1 at accept time.

Net: the loop TODAY writes better prompts than the July-era loop, equally
styled solutions and harnesses, and ~60% of the retrofitted harness depth —
with the missing 40% concentrated precisely in the scheduling/lifecycle pins
the catch-up campaign paid a month to learn matter.

---

## 2. Variations — INTERIM (all three ACCEPTED; FIM/derived still running)

New set: `015_002_sliding_window_failure_count`, `015_003_dependency_aware_
cascading`, `015_004_concurrent_sweep` (3, 2, 2 attempts). All distinct from
the base and from each other (gate 1/9), all graded on a blind Step-B solution
(gate 2/9, row 8 ENFORCED).

### The enforced gates visibly earned their keep

- The per-function mutation gate REJECTED two first drafts for an uncovered
  `handle_cast/2` and forced real harness strengthening (015_002, 015_004).
- The test-floor check rejected two drafts at 12 tests vs 14 public functions.
- Repair fixed exactly what the report named; nothing else regressed.

### F17-6 (rows 13/14 nuance): the timer-leak class is a COIN FLIP, not a constant.

015_002 and 015_003 both solve the re-registration problem CORRECTLY with
epoch-tagged ticks (`{:tick, name, epoch}`; stale epochs are dropped and not
rescheduled — old chains die at their next fire). The base got the same
problem wrong the same afternoon. Same loop, same templates: whether the
lifecycle hazard is handled is model luck, per unit. A template hint alone
would raise the hit rate; only an accept-time check (a lifecycle test
requirement, or a judge) makes it a floor.

### F17-7 (row 13, systematic): the replace/reset promise is now TEMPLATE
PROSE — and is never tested.

All four new prompts (base + 3 variations) contain the same sentence pattern:
"<Registering/Watching/Enrolling> a `name` that already exists replaces its
configuration and resets it to this initial state." ZERO of the four
harnesses test it. A promise the template reliably emits and the harness
reliably skips is the cheapest possible checklist item (T1.4) — and it is the
exact hole F17-1 shipped through.

### F17-8 (015_004, row 14/16 borderline): "slow probes cannot block one
another" — but one hung probe blocks the whole sweep forever.

The concurrent-sweep design gathers probe results with a bare `receive` (no
`after`); `sweep/1` is documented to block until every probe finishes, so a
never-returning probe hangs the server permanently. Raises/throws ARE handled
(prompt-promised, shielded). Nothing in the prompt promises tolerance of
never-returning probes, so this is contract-defensible — but the prompt's
headline claim is stronger than the semantics, and the OLD async-timeout
variation existed precisely to engineer this away (`:timeout_ms`, kill the
task, treat as failure). Difficulty drift, same direction as the base's:
the regenerated family is systematically EASIER than the retrofitted one.

### F17-9 (row 10 scope note): the dark blind re-screen is BASE-ONLY.

All three variations were repaired accepts. Their attempt-0 solutions were
blind (row 8), but repairs happen AFTER the blind solve and may edit the
harness; `GEN_BLIND_RESCREEN` as built (GenTask.Base) would not re-screen a
repaired VARIATION even once flipped on. T1.1's sign-off should decide
whether the re-screen covers "bases only" or "any repaired accept" — the
§5.2.2 entailment judge over repair-time harness diffs (row 11) is the other
instrument aimed at this window.

## 2b. FIM / derived shapes — PENDING

Findings land here when the run exits.

## 3. Candidate generator gates (rule 7 Task-B list — to be finalized)

From the base unit alone:

- **G-A (from F17-1/F17-2): accept-time promise-coverage judge** — one LLM
  call per accepted base/variation: "list every behavioral promise in
  prompt.md; for each, name the harness test that exercises it; output the
  uncovered ones". Uncovered ≠ auto-reject necessarily — start report-only,
  then decide a threshold. This is the hard version of parity row 13, and it
  would have flagged the exact hole F17-1 shipped through (re-registration
  documented, untested).
- **G-B (from F17-1): a timer/resource-hygiene checklist item in T1.4's
  harness-rule constant** — any prompt promising replace/cancel/deregister
  semantics for scheduled work must carry a test that pins the old schedule
  is dead (the F12/F17-1 class, now seen twice in one family).
- **G-C (from F17-3/F17-4): T1.4 template upgrades** (exemplar rotation,
  doctest+property request) — already designed in docs/12 §5.3, this probe
  adds fresh evidence they're load-bearing.
- **G-D: flip decisions** — rows 10/12 are BUILT and dark; the probe shows
  what "dark" costs in the accept log itself. Kamil's sign-off is the only
  remaining step for both.

*(This list is finalized in §4 after the full family lands.)*
