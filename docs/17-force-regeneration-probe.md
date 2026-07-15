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

*("Dark" = fully built and wired into the loop but switched OFF by default via
an environment variable, so behavior is unchanged until Kamil turns the switch
on — see the glossary in docs/11.)*

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

## 2b. FIM / derived shapes — COMPLETE (run finished 13:57, ~50 min wall)

Full-run totals (this run's `runs.jsonl` window; every verdict also in
`logs/gates.jsonl`, 339 rows): **75 accepted** — 1 base + 3 variations +
12 fim + 40 tfim + 4 wtest + 12 bugfix + 3 adapt — with 8 in-flight
rejections (3 tfim, 5 bugfix), 27 Opus calls, ~152k output tokens. The family
converged to EXACTLY the old family's shape counts (16/4/40/12/3) — the caps
drive corpus shape, as designed. Repair minting correctly declined to mint
from this run's one repair chain (a style-only fix is not a bug→fix pair).

Spot checks (rule 8, by eye): the bugfix pairs carry real captured failing
reports that match their seeded one-line bugs; adapt pairs embed the base
gold verbatim and pass the RED gate (base gold red under every variation
harness); wt/tfim embeds match their parents byte-for-byte.

### F17-10 (the cascade in numbers): one bad root became 20 defective-context children.

The base's leaky module is now embedded verbatim in: 3 fim children (as the
skeleton context), 10 tfim children (module under test), 1 wt gold
(module-to-test), 3 bugfix golds (the "fixed" side STILL carries the
unrelated latent leak), and 3 adapt starting points. None of the derived
gates re-judge parent semantics (by design — they inherit); so root quality
is a MULTIPLIER: every semantic defect that slips the root gates ships ~20
training artifacts. The accept path for roots is where all marginal gate
budget should go.

### The free instruments all pass the regenerated family — and that is the point.

`validate` (perfect) / `--mutants` / `--fim`: exit 0 across all 75 units.
Format gate: 0 deviating. tfim/bugfix/adapt embed-drift dry runs: clean
(row 19 holds for fresh mints). The deterministic suite is honest AND
insufficient: everything it checks, the loop already produces; everything
this probe caught (F17-1, F17-2, F17-7, F17-8), it structurally cannot see.
The docs/12 §5.5 cutover instruments (semantic_review + rubric_judge on new
roots) are the only listed checks that could have flagged the leak — they
are exactly the two rows (13/14) still reading NOT ENFORCED.

## 3. Final candidate generator gates (rule 7 Task-B list)

Ranked by (evidence strength × cheapness):

- **G-A — accept-time promise-coverage judge (rows 13/16; from F17-1/2/7).**
  One LLM call per accepted ROOT (base/variation only — F17-10 says roots are
  the multiplier): "extract every behavioral promise from prompt.md; name the
  harness test exercising each; list the uncovered". Start report-only into a
  ledger; flip to reject-on-uncovered once the false-positive rate is known.
  Would have caught the exact holes F17-1 and F17-7 shipped through. Cost:
  ~1 call/root ≈ the blind re-screen's budget.
- **G-B — lifecycle/timer checklist item in T1.4's shared harness rule
  (row 17; from F17-1/6).** Any prompt promising replace/cancel/deregister
  semantics over scheduled work must require a test pinning the old schedule
  dead. Free, template-side; raises the hit rate G-A then enforces.
- **G-C — T1.4 as designed (rows 21 + doctests; from F17-3/4).** Exemplar
  rotation + doctest/property request + difficulty push (F17-5/8's drift is
  the new evidence for §5.3(d)).
- **G-D — flip the two dark flags (rows 10/12).** Built, tested, SKIPPED
  lines now visible in every accept log. Sign-off is the only remaining step.
  T1.1 scope question from F17-9: bases only, or any repaired accept
  (variations included)?
- **G-E — cutover acceptance test unchanged (docs/12 §5.5 bottom).** This
  probe ran only the free half. The first REAL Phase-3 batch still needs the
  LLM instruments (semantic_review every root + rubric_judge two-family) —
  the probe demonstrates they are load-bearing, not ceremonial.

## 4. Bottom line

At today's bar the loop produces: better prompts than the retrofitted era
(near-formal contracts, documented determinism seams, blind-solvable
attempt-1), equally styled code, fully enforced deterministic gates (every
row 1–9/18/19 verdict printed and ledgered) — and **semantic quality that is
still luck**: 1 probe-proven lifecycle bug in 4 roots, a template promise
that is never tested (4/4), and a measurable difficulty drift toward easier
designs. Phase 3 at "no second month" quality needs G-A/G-B/G-C landed and
G-D flipped BEFORE the throttle opens; the parity table's remaining rows are
precisely where the probe's defects went through.

**Probe disposition:** the regenerated family is archived at
`logs/probe_015_regenerated_2026-07-15.tar.gz` (237 files). The retrofitted
family is restored with `git checkout -- tasks tasks/tasks.md` once Kamil has
finished inspecting the live diff. The probe data must NOT be exported for
training (F17-1 is known-defective); restore before the next export.

---

## 5. THE ANSWER (Kamil's question, direct): is the regenerated family at our
## standard, and can the manual quality process be replicated in the loop?

### 5.1 Verdict: NO — below standard on exactly three dimensions; at or above
### standard on everything else.

Below the retrofitted bar:

1. **Lifecycle correctness.** The old base cancels + drains timers
   (probe-proven, F12); the new base leaks chains on re-registration
   (probe-proven, F17-1). 1 of 4 new roots carries a real behavior bug.
2. **Harness depth.** 12 tests vs 21. The missing nine are not random — they
   are precisely the retrofit's additions: the timer trio (first-check
   timing, re-arm, cancellation), stale-message, re-register-reset,
   notification-reason accuracy, timestamp tracking. The floor gate
   (max(3, public fns)) accepts roughly HALF the depth the campaign
   established as the bar.
3. **Design richness.** No deregister, binary status instead of status_info,
   a sweep that can block forever where the old variation engineered
   timeouts. The loop takes the easiest valid reading of an idea.

At or above the bar: prompt precision (better than the old era), style,
formatting, mutation coverage, stability, blind-solvability, derived-shape
integrity. The deterministic standard IS met; the SEMANTIC standard is not.

### 5.2 How each deficit was fixed MANUALLY — and its in-loop replica.

The catch-up month was not magic; it was four repeatable mechanisms. Each has
a mechanical equivalent that reuses plumbing the loop already has:

| # | deficit | the manual mechanism that fixed it | the in-loop replica |
|---|---|---|---|
| 1 | untested prompt promises (F17-2/7; T2.2's ~74) | `close_gaps.exs`: an LLM read prompt+harness, listed promises with no test, wrote ADD-ONLY tests, and every added test was **bite-proven** (made to fail against a deliberate behavior break, pass against gold) before it shipped | **In-loop coverage closer** (`GEN_COVERAGE_CLOSE`): after today's gates pass on a ROOT, one call proposes the uncovered-promise tests; each proposed test must (a) pass vs the gold and (b) fail vs a targeted break — reusing `Mutation`/eval plumbing and `guard_test_deletion`. Grown harness re-runs the mutation+stability gates. This is close_gaps' exact flow, moved from retro to accept time — the same porting pattern that took lint_harnesses' detectors into `quality_shortfall` (parity row 6). |
| 2 | semantic defects on green tasks (F12, T2.4-T, F17-1, F17-8) | `semantic_review`/`rubric_judge` flagged suspects; a HUMAN then probe-proved each flag before any edit (rule 8's verify-before-verdict) | **Evidence-or-drop review judge** (`GEN_SEMANTIC_JUDGE`): one call per root — "find behavior bugs the tests miss, doc claims that lie, lifecycle hazards; for EACH claim emit a minimal ExUnit test that should FAIL if the claim is real". Run each test against the gold: fails → the finding is machine-proven → feed it into the EXISTING repair loop as the report; passes → judge hallucination, drop silently (F6-proof). This mechanizes precisely how F17-1 was found in this probe (read → suspect → probe → prove) with zero human in the loop. |
| 3 | weak-kill harnesses (S8 tail) | `strengthen_harnesses.exs` + survivor naming → added discriminating tests | **ALREADY BUILT DARK** — `GEN_SEMANTIC_FLOOR` + survivor-naming repair reports (scar #4). Flip = sign-off. |
| 4 | repaired accepts with no blind evidence (6/22) | `rescreen_repaired.exs` retro-screened them | **ALREADY BUILT DARK** — `GEN_BLIND_RESCREEN`; extend scope from bases to any repaired root (F17-9), then flip. |
| 5 | prompt↔harness API gaps | `lint_harnesses --fix-prompts` + `enrich_prompts` | **ALREADY PORTED** (quality check 17/17) — held in this probe. |
| 6 | design richness / difficulty | never fixed manually — the old family was BORN richer; the retrofit only deepened harnesses | template-side only: T1.4 exemplar rotation + an explicit lifecycle clause in the base template ("specify AND test register/replace/cancel semantics for any scheduled work" — G-B). The coverage closer (#1) also punishes thin designs indirectly: every promise costs a test. |

### 5.3 Why this is affordable and where it runs

Both new stages run on ROOTS ONLY (F17-10: roots are the ~20× multiplier;
children inherit). For this family that is 4 units → ~5–8 extra calls +
~10 evals on top of today's 27 calls (~25% cost growth) for the two
mechanisms that address every probe finding. Both slot into the existing
accept path AFTER stability, BEFORE promotion, as GateLog-numbered gates on
the :base/:variation manifests; both land DARK behind flags first (the
T1.1/T1.8 precedent), then flip after a pilot family.

### 5.4 The claim to test at cutover

With #1 + #2 landed dark and piloted, and #3 + #4 flipped: re-run THIS probe
(`generate.exs 15 --force` again, or a fresh family). Prediction: the
coverage closer forces the re-registration test into existence, which either
catches the leak at accept time (repair fixes it) or the judge's probe does.
If a re-probe still ships a semantic defect, the cutover instruments
(semantic_review + rubric_judge, G-E) remain the backstop — but the loop
should now pass them on batch one, which is the "no second month" contract.

### 5.5 BUILD NOTE (2026-07-15 evening, T1.10 LANDED DARK — one stage, not two)

Mechanisms #1 and #2 collapsed into ONE gate during implementation:
`GenTask.PromiseAudit` behind `GEN_PROMISE_AUDIT` (default off). The insight:
"find bugs the tests miss" and "test the untested promises" are the same ask —
every observable defect IS a missing test that fails against the gold. One
auditor call per root returns anchored test blocks; the machine then decides
what each one is:

    anchor quote must appear verbatim in prompt.md (≥25 chars, ws-normalized)
      → else dropped (a test may only pin PROMISED behavior)
    staged alone vs the gold:
      green → must bite (kill ≥1 raise-mutant in isolation — the tfim gate,
              siblings AST-stripped) → kept as COVERAGE, else dropped vacuous
      red   → kept as MACHINE-PROVEN DEFECT (evidence-or-drop; a hallucinated
              claim can never act — F6-proof by construction)
    kept blocks merged (anchors stripped — S10 chatter rule) → the grown
    triplet re-runs the FULL shared cycle: a proven defect forces the fixer
    to repair the module against a failing test it cannot delete; the grown
    harness re-proves green + house style + mutation + stability.

Also landed with it: the blind re-screen now covers repaired VARIATIONS
(F17-9 scope fix, same dark flag), and the `:quarantined` outcome no longer
crashes the console printer (a latent T1.1 defect found by code reading).
The audit re-cycle logs attempts under `<id>_audit`, so the original attempt
chain (repair-mint raw material) is preserved. 385 tests green, including two
end-to-end audit paths against the real evaluator: a coverage candidate
vetted+merged, and a planted identity-promise violation machine-proven and
repaired by the cycle. Rows 13/14 of the parity table now read BUILT DARK.

---

## 6. PILOT VERDICT + THE DEFAULT-ON POLICY (2026-07-15, late afternoon)

### 6.1 The §5.4 prediction confirmed VERBATIM on the audit's first outing.

The audited pilot (`GEN_PROMISE_AUDIT=1 … 15 --force`,
`logs/force_015_audited.log`) regenerated the base; it passed gates 1–6 on
attempt 0 (12 tests, 8 public functions). Then gate 7/9, the promise audit,
on its FIRST production call:

    promise test "re-registering with a longer interval stops the old
                  interval's timer" ... KEPT (defect)     ← the F17-1 class
    promise test "with auto_check disabled no automatic check runs on its own" ... KEPT (coverage)
    promise test "auto_check defaults to true when the option is omitted" ... KEPT (coverage)
    promise test "the other functions may be called with the registered name" ... KEPT (coverage)
    promise test "an unexpected message does not alter accumulated failure state" ... KEPT (coverage)
    → re-cycle: 16/17 (the defect test FAILED vs the gold) → repair →
      17/17 green, all 8 per-function mutants killed, stable →
    gate [7/9] PASS — harness 12→17 tests; module repaired against the proven defect

The fresh base had AGAIN shipped the uncancelled-timer class — and this time
it died at accept time, machine-proven and machine-fixed, no human involved.
The four coverage tests are line-for-line the F17-2 gap list (named
registration, option default, no-auto-when-disabled, unexpected-message
robustness). This one trace is the whole probe's thesis demonstrated.

### 6.2 Kamil's standing policy: quality gates are NEVER optional.

Kamil, on being shown "dark flags": *"if there are some things that
generation could do to increase the quality of the output — it NEEDS to do
that — I don't see a scenario where I would want to spend my tokens on
'suboptimal' results."* Encoded immediately (and in the agent's persistent
memory): `GEN_BLIND_RESCREEN` and `GEN_PROMISE_AUDIT` resolve ON by default;
`GEN_SEMANTIC_FLOOR` defaults to **0.6** (rejects the measured corpus tail:
68 families were below 0.6; Kamil may tune the number). The switches remain
only as debugging overrides and print `SKIPPED — EXPLICITLY DISABLED` when
used. Parity rows 10/12/13/14 now read ENFORCED. The audit-only pilot was
stopped after its base (partial output stashed) and relaunched with ALL
gates on → `logs/force_015_full.log`; its verdict lands here as §6.3.
