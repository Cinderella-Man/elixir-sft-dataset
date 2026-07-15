# PROJECT STATUS — the live work list (read after CONTEXT.md's HOW-WE-WORK rules)

**HARD RULE (CONTEXT.md rule 5): this file contains ONLY todo / in-progress /
blocked items — NOTHING that is done.** Completed work moves immediately to
`docs/15-completed-work-log.md` (and lives in git history). The point of this
file is to find all the things that need work, at a glance. Update it AS YOU
GO — before launching a job, after finishing one — never "at the end".

Reference docs: `docs/14` (full handover: gates, tools, ledgers, runbooks),
`docs/12` (quality standard S1–S12), `docs/13` (data-extension designs).

---

## ▶️ RUNNING RIGHT NOW

**T1.9 (Kamil 2026-07-15): gate transparency + `--force` regeneration probe.**
Builds (a) verbose gate logging and (b) `generate.exs <n> --force` are DONE →
docs/15 on close. Probe (c) RAN TO COMPLETION (75 units, ~50 min, 27 calls,
all free instruments green) and the analysis is in **docs/17** (findings
F17-1..10, candidate gates G-A..G-E). Remaining, in order:
  - [x] T1.10 BUILT DARK — i.e. fully built + tested but OFF by default
        behind an env-var switch; zero behavior change until the switch is
        set (glossary: docs/11). (2026-07-15 evening; docs/17 §5.5; 385
        tests green):
        ONE unified gate `GenTask.PromiseAudit` behind `GEN_PROMISE_AUDIT` —
        anchored audit tests; green→bite-proven coverage, red→machine-proven
        defect feeding the repair loop; + F17-9 rescreen now covers repaired
        variations; + `:quarantined` console crash fixed (latent T1.1 defect).
        Parity rows 13/14 → BUILT DARK.
  - [x] AUDITED PILOT, first outing (2026-07-15 afternoon, docs/17 §6): the
        §5.4 prediction confirmed VERBATIM — the audit's first production run
        machine-proved a timer-leak defect on the fresh base ("re-registering
        … stops the old interval's timer" failed vs the gold), the repair
        loop FIXED the module against it, and 4 more promise tests were
        bite-proven and merged (harness 12→17). The F17-1 class now dies at
        accept time.
  - [x] **QUALITY GATES NOW DEFAULT-ON (Kamil 2026-07-15: "quality gates are
        never optional — I never want tokens spent on suboptimal results").**
        GEN_BLIND_RESCREEN + GEN_PROMISE_AUDIT resolve ON, GEN_SEMANTIC_FLOOR
        defaults 0.6 (Kamil may tune the number; `=off`/`=0` switches are
        debugging overrides only). Parity rows 10/12/13/14 → ENFORCED.
        REMAINING: the full-standard probe below.
  - [x] FULL-STANDARD PROBE #3 (docs/17 §6.3): the system REFUSED to ship —
        audit repaired the timer leak (3rd occurrence today), then the blind
        re-screen proved the PROMPT doesn't state the old-chain-stops
        consequence (independent solver leaked too) → QUARANTINED, nothing
        promoted. Triage verdict: prompt-TEMPLATE gap → generator fixed
        (LIFECYCLE RULE now in base+variation templates — G-B landed).
  - [x] PROBE #4 (docs/17 §6.4): **the family was born at the bar** — 75
        units, ONE repair call total, zero audit-proven defects, all four
        re-screens green, floors 0.72–0.93, lifecycle rule propagated into
        every prompt+harness, base probe-proven leak-free. Free-instrument
        sweep running (`logs/verify_015_probe4.log`) — verdict appended to
        §6.4 when done.
  - [x] T2.6-PILOT DONE (2026-07-15 evening → docs/15): all four 015 root
        prompts at contract precision, 4/4 blind screens GREEN, F18 found +
        probe-proven + FIXED en route, every cascade applied and gate-clean,
        pushed. Open decision for Kamil: extend the prompt-precision round
        corpus-wide (T2.6 proper — the pilot measured ~1 screen call/root and
        found 1 latent gold bug in 4 roots; at that hit rate the remaining
        ~299 roots hide more F18s).
  - [ ] **NEW BUILD ITEM (from §6.3): in-loop quarantine-triage path** — the
        loop can quarantine but has no "hard-task KEEP" verdict (the retro
        screen had 49 keeps). Phase 3 needs: triage judge over
        `logs/quarantine/*` + Kamil review + a keep-promotion path writing
        the evidence row. Until built, quarantines block their idea and
        surface here.
  - [ ] Kamil decisions still open: T1.6 Dialyzer (one mix.exs line),
        semantic-floor NUMBER tuning (running default 0.6), T2.2 full-pass
        question, nightly-sweep timer. (T1.4 landed 07-15 evening —
        docs/15.)
  - [ ] On close: move T1.9/T1.10 record to docs/15; keep `--force` + GateLog
        + PromiseAudit as permanent loop features.
---

## ⏭️ IMMEDIATE QUEUE (in order; updated 2026-07-15 early morning)

1. **Kamil's five decisions** (section below) — they gate Phase 3, T1.1,
   T1.6 (and TD.3 behind it), the nightly timer, and the T2.2 full-pass
   question. Nothing else blocks them.
2. Bigger builds: the **TD.2–TD.4** decisions (TD.1 closed — docs/15).

*(F10-A + T2.4 measurement + T2.4-T (all 5 flags) + F12 + T1.7 + T1.8
closed 07-14/15 — docs/15.)*

## 📋 QUALITY TODO REGISTER (2026-07-13 — why / what / how / cost per item)

An item leaves this list only when done (→ docs/15) or when Kamil kills it.
"FREE" = CPU/engineering only, no API calls.

**HARD RULES (CONTEXT.md rules 7–10):** every finding = **TWO EXPLICIT
TASKS** (Task A: fix the existing data; Task B: gate the generator so it can
never recur) — the problem leaves STATUS only when BOTH are done; spot-checks
run on accepted AND rejected data; every full-dataset run gets a
detail-reviewed pilot first; every solved item is removed from here and
committed immediately (one solved item = one commit).

### 🔎 OPEN FINDINGS — two tasks each

**F12 — 015_001 lying deregister @doc + resurrectable check chain.**
- F12-A (fix data): DONE → docs/15 (07-15: tracked timer refs + cancel +
  drain, probe-proven, full cascade, bugfix children reminted).
- F12-B (gate generator): prose-claims-need-pins half DONE 07-15 (T1.4
  COVERAGE/LIFECYCLE/CALLBACK rules + the default-ON promise audit —
  docs/17). REMAINING: the @spec half = T1.6 Dialyzer (Kamil's mix.exs
  line).

*(Closed with both tiers done — see docs/15: F1 — repaired-accept gaps
(T1.1 re-screen default-ON 07-15); F10 — promise-coverage gap (T1.4
COVERAGE RULE + default-ON promise audit, 07-15); F2 — blind evidence staled by
harness edits; F3 — reject rows surviving their gate's repair; F4 — tools imitating grandfathered anti-patterns; F5 —
generation-process chatter; F6 — LLM-judge hallucinated verdict; F7 —
environmental failures as verdicts.)*

### Tier 1 — make every FUTURE generated unit better (loop + gates)

*(T1.1 CLOSED 07-15 — the blind re-screen is default-ON for repaired bases
AND variations; docs/15. Not built, discuss if post-cutover audits show
residual leakage: the §5.2.2 entailment judge over repair-time harness
diffs, and a CI check refusing accepts lacking the evidence row.)*

**T1.4 — Phase 3 template upgrades: LANDED 2026-07-15 (Kamil: "improve
everything") except sliver (d).** Done → docs/15: (a) ONE shared
harness-rule block for base+variation templates (COVERAGE / API-SHAPE /
LIFECYCLE / CALLBACK rules); (b) doctest + property-test request; (c)
3-exemplar shape rotation + vary-the-register instruction. REMAINING
sliver: (d) record each seed's blind-screen outcome as difficulty
metadata (ledger-side, tiny — fold into the export work).


**T1.6 — Dialyzer gate over the golds. [NEEDS KAMIL: one mix.exs/lockfile
change; then FREE (PLT build + weekly CI)]**
- WHY: 019_001 shipped a `@spec` contradicting its own code; specs must be
  machine-checked. Hard prerequisite for the dedoc shape (docs/13 §2.3, ~331
  free units) — wrong specs must never become training targets.
- WHAT/HOW: add `dialyxir`, one-time PLT, driver staging each gold with its
  deps, weekly CI gate. Pilot on 5 families first. Design: docs/13 §2.6.


### Tier 2 — raise EXISTING corpus quality (evidence says more is there)


**T2.6 — Prompt-register monotony rewrite (improvement round #2 — do NOT
start before steady state). [BIG: 2,396 tfim + 302 wt_ + 80/332 seed openers;
own tool + ledger + blind re-screen budget]** — docs/12 §7.4;
frozen-template overfitting is a documented SFT failure mode.

### Tier 3 — protect the TRAINING side

*(empty — T3.1 was the only item; the next training-side item lands here
when a training run is planned.)*

### Data extension (docs/13 §2 — build order after Tier 1)

**TD.2 — Multi-turn repair-dialogue exporter** (PERISHABLE raw material —
snapshot `logs/attempts/` before any big run; archives exist from
2026-07-12 AND 2026-07-14b, the latter taken right after the TD.1 mint;
the backfill's repair-mint tail now reads 745 chains / 100 mintable
rejected→accepted pairs). docs/13 §2.2.

*(TD.1 adapt pairs: CLOSED 2026-07-14 late — 249/249 minted, ALL PERFECT;
docs/15.)*
**TD.3 — dedoc** (blocked on T1.6 Dialyzer). docs/13 §2.3.
**TD.4 — style-repair pairs (207) + cap lifts (~1,900 free tfim)** — decide
against docs/16 §4's advisory weights (test_fim already down-weighted to
0.25; a cap lift adds volume in the most-discounted shape). docs/13 §2.4–2.5.

---

## 🧍 WAITING ON KAMIL (decisions only — nothing else blocks Phase 3)

1. *(resolved 07-15 by Kamil's default-on directive: the blind re-screen
   and promise audit run always; the semantic floor runs at 0.6 — tune the
   NUMBER if you want a different bar.)*
2. **docs/12 §4.2 sign-offs, remaining halves** — spot-review scope and
   prompt-monotony scope (the semantic-floor half is now the 0.6 default).
3. **Nightly-sweep systemd timer install** — 4 commands, docs/12 §4.1.10.
4. **T1.6 Dialyzer** — one `mix.exs` + lockfile change. (Two more live
   would-have-caught cases from today's T2.2 batch: 038_001's undocumented
   `duplicate_ids` return violating its own @spec; 043_001's named-table
   atom vs declared `:ets.tid()` type.)
5. **T2.2 full-pass decision** — the 60-root batch says 88% of roots carry
   ≥1 confirmed finding (~1.5/root → ~490 corpus-wide). All 89 batch
   findings are already FIXED (T2.2-T closed 07-14 — docs/15).
   RECOMMENDATION: do NOT pay the remaining ~272-root review (~16M
   tokens) — the classes are known and dominated by promise-coverage debt;
   spend instead on T1.4's checklist, and re-review a small sample AFTER it
   lands to verify the class is closed.

## Current mode: 🔧 CATCHING UP (improvement round #1, 2026-07)

New base generation is **paused**. Remaining exit conditions for this round:

- [ ] §4.2 / §5.2 decisions signed off (above)
- [ ] **LOOP PARITY (docs/12 §5.5 — Kamil 2026-07-15: "new data must be
      born at the bar we are retrofitting"): every row of the parity table
      reads ENFORCED or is explicitly waived by Kamil.** Free builds toward
      it: T1.7 + T1.8 + T-gates below; decision rows ride the sign-offs.
- [ ] Phase 3: new generation resumed (490 queued bases) and the first
      batch passes the **cutover acceptance test** (docs/12 §5.5 bottom):
      full semantic_review of every new root + a rubric_judge two-family
      pass + all sweeps — ZERO triage-grade findings, else stop and fix
      the GENERATOR, never the data
- [ ] The line drawn (docs/12 §7.2): delete catch-up tooling
      (`rescreen_repaired.exs`, `strengthen_harnesses.exs`,
      `enrich_prompts.exs`, `quality_chain*.sh`, `close_gaps.exs`,
      `survey_adapt_redgate.exs` et al. per the §7.2 table and the docs/14
      disposition table; the four resync DRIFT GATES and the standing
      audits stay), remove the backfill vocabulary, flip this file to
      STEADY STATE

Everything previously listed as done in this round: `docs/15-completed-work-log.md`.

## The two modes (definitions)

**STEADY STATE** — one command produces new data
(`scripts/run_detached.sh logs/loop.log mix run scripts/generate.exs`), every
quality check lives inside that loop or in CI, and nothing needs to be "caught
up". No backfill tooling exists in the repository.

**CATCHING UP (improvement round #N)** — we raised the quality standard, so
existing data must be brought up to it. Protocol: docs/12 §7.3 (bump standard
→ wire check into loop+CI FIRST → one-shot ledgered upgrade tool → run to
completion → verify whole corpus → delete the tool → flip this file back).

## Round history

| # | Round | Dates | What was raised | Status |
|---|-------|-------|-----------------|--------|
| 1 | 2026-07 QA catch-up | 2026-07-07 → … | prompt↔test consistency, mutation & format gates, embed staleness, blind screening (docs/10) + S6 freshness, reject-ledger audits, semantic floor closed (docs/15) | **in progress** |
