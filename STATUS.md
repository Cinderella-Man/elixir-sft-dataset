# PROJECT STATUS — read this first

This file is the single place that says what the project is doing **right now**.
It answers one question: are we **producing new data**, or are we **catching up**
on a quality improvement? Update it whenever the answer changes; everything else
(docs, scripts, plans) is secondary to this file.

---

## Current mode: 🔧 CATCHING UP

**Improvement round #1 — the 2026-07 quality-assurance catch-up.**
New base-task generation is **paused**. The plan of record is
`docs/11-catch-up-plan.md` (phases) + `docs/12-quality-standard-and-steady-state.md`
(the concrete work list, the quality standard, and the exit protocol).

What that means in practice:

- **Allowed now:** deterministic corpus fixes, gate hardening, validation sweeps,
  the scope decisions listed in docs/12 §4.
- **Next (Phase 2):** one derivative top-up run
  (`GEN_ONLY=backfill scripts/run_detached.sh logs/backfill.log mix run scripts/generate.exs`)
  — only when docs/12 §4 items marked **[blocks Phase 2]** are done.
- **Then (Phase 3):** new base generation (490 queued ideas) — only when Phase 2
  is complete and the loop-hardening items marked **[blocks Phase 3]** are done.
- **Then: draw the line** (docs/12 §7): delete the catch-up tooling and the
  backfill vocabulary, and flip this file to STEADY STATE.

### Checklist to exit this round

- [x] Stale child-prompt copies resynced + staleness gate wired (docs/11 §1a, 2026-07-10)
- [x] Seed self-check fixed, 50 blocked units freed (docs/11 §1b, 2026-07-10)
- [x] Corpus format gate green again (23 embeds, 2026-07-10)
- [ ] docs/12 §4.1 deterministic punch list — DONE 2026-07-10: 020_001 rebuild
      (re-screen GREEN), 001_002 reach-in, chatter sweep (4 families), fence
      artifacts, 23-tfim re-gate (0/23), repair audit (0 flags), semantic
      re-measure (tail = 20 <0.5), register metric, backfill-script removal;
      001_004 redesign (re-screen GREEN), §4.1.3 per-fn+init/1 sweep (ZERO
      survivors across 1,612 evals — populations #1/#2 closed empty);
      §4.1.9 decontamination gate (0 exact / 0 near-miss vs 786 benchmark
      rows); STAGED: nightly-sweep systemd units (needs install, §4.1.10).
      **§4.1 is COMPLETE** except the staged timer install.
      **Every [blocks Phase 2] item is now done — Phase 2 top-up is ready to
      launch on Kamil's go (paid run).**
- [x] docs/12 §4.2.1 — 099_002/3/4 screened GREEN; S6 holds for all 303 seeds (2026-07-10)
- [ ] docs/12 §4.2 decisions signed off (spot-review scope, prompt-monotony scope, semantic floor — tail confirmed at 20 families <0.5 by re-measure)
- [x] docs/12 §5 loop hardening §5.1 — ALL DONE (items 1–7 2026-07-10; item 8
      gate + classification 2026-07-11; remediation + CI wiring 2026-07-12:
      **embed check 1266 clean / 0 reflow / 0 drift, gated in CI**). Still
      OPEN: §5.2 decision (accept-time blind screen for repaired bases +
      entailment judge) — needed before Phase 3
- [ ] Phase 2: derivative top-up run **LAUNCHED 2026-07-10 ~18:45** (detached,
      `logs/backfill_phase2.log`; 111 seeds / 710 units: 29 variation + 57 FIM
      + 624 test-FIM). First run through the §5.1-hardened loop. Died
      2026-07-11 14:18 during a usage-limit wait (old session teardown);
      **relaunched 2026-07-11 17:07** with the same command — the work
      registry resumed it at 87 seeds still needing top-up (24 seeds finished
      in the first stretch; ~101 units were pending at relaunch: 6 variation +
      19 FIM + 3 write-test + 73 test-FIM). Complete when
      `mix run scripts/work_status.exs --counts` shows 0 pending everywhere
- [ ] Phase 3: new generation resumed and first batch validated
- [ ] The line: catch-up tooling deleted per docs/12 §7.2, this file flipped

### Where we are right now (2026-07-11 ~22:30 — allowance is back, working in small committed batches)

Two things are in flight; both survive interruptions without losing work:

**1. Phase 2 top-up keeps running on its own.** The detached loop (PID in
`logs/backfill_phase2.pid`, log `logs/backfill_phase2.log`) rode out today's
~4.5-hour usage-limit window with its 15-minute retries and resumed by itself
at ~22:11 (currently grinding 019_001 FIM units). Do not restart it while a
`beam.smp` process is alive. If it has actually died (no beam process, log not
growing), relaunch the exact same command; it is idempotent:
`GEN_ONLY=backfill scripts/run_detached.sh logs/backfill_phase2.log mix run scripts/generate.exs`.
Accepted output is now committed in batches as it accumulates (complete dirs
only — a dir written in the last few minutes is skipped until the next batch).

**2. docs/12 §5.1 item 8 (embed staleness gate) — DONE 2026-07-11 ~23:15.**
Full detail in docs/12 §5.1; short version:

- `scripts/check_embeds.exs` final: conventions a–g plus i–m from the drift
  classification, two checker bugs fixed (indented example fences swallowing
  the module fence; wt_ `<file>` wrapper on non-bundle parents). Verified
  deterministically: planted-phantom self-test green, per-rule expected dirs
  clear, full-corpus before/after diff has ZERO clean/reflow→drift
  regressions.
- Classification complete for all 64 families (55 recovered from the killed
  workflow's journal + 9 re-run in two small batches). Ledger:
  `logs/embed_classify/recovered.jsonl`. One LLM claim ("@spec omission is a
  mint convention", 089_002) was REFUTED by git history and rejected — the
  refuter-agent pass was replaced by deterministic verification (checker
  re-run + git archaeology), which was both free and stricter.
- **Corpus verdicts now: 1068 clean / 46 reflow / 137 real drift** (was
  933/162/156 this morning; 126 one-line "reflows" turned out to be myers
  seam artifacts, not stale embeds). The 137 = 122 resync_embed +
  12 fix_child_gold + 3 one-token wt_ drifts (see ledger for per-dir
  verdicts).
- **Remediation is built, tested, and queued to run the moment Phase 2
  finishes** (Kamil's overnight go, 2026-07-11 ~23:30: "keep on working").
  `scripts/resync_embeds.exs` (one-shot catch-up tool, delete at the line):
  module-FIM = deterministic skeleton rebuild via `EvalTask.Fim`
  (bundle parents marker-stripped; reflow-stale golds rewritten from the
  parent first); wt_ = full refresh via `GenTask.WriteTest.prompt_md/2` +
  byte-copies of solution/harness/manifest. Dry-run default; `--apply`
  REFUSES while a generate.exs BEAM is alive; per-file backups in
  `logs/embed_resync_backup/`; ledger `logs/embed_resync.jsonl`; idempotent.
  Self-tested in scratch on all five shapes (fim reflow, wt_ reflow, @spec
  drift, one-token wt_ drift, gold-rewrap) — all resync → CLEAN, second run
  no-op; a redesigned-parent dir errors, never auto-writes.
  Dry run over the 183 flagged dirs: **171 would resync + 12 hand-fix
  errors, exactly the ledger's fix_child_gold set** (021_001_03,
  034_001_02/03/04, 038_001_02, 039_001_02/04, 072_001_03, 091_001_03,
  091_002_03, 091_003_04, 131_003_04).

### Overnight runbook — EXECUTED 2026-07-12 03:38–05:00 ✅

The Phase 2 loop's first pass finished cleanly 03:38 (its 87-seed list done;
`Done.` + auto repair-minting: 10 new repair_ tasks). All remediation steps
ran to completion while no loop was alive — see the git log
(`985f6e54`…`2148a14d`): 84 accepted dirs committed, 171 embeds resynced +
validated, 12 redesigned-parent golds hand-fixed + re-gated, one real lib bug
fixed en route (`EvalTask.Fim.signature_stub` continuation-`do:` corruption),
**embed check 1266/0/0, CI gate live**, mix test 254 green.

**Phase 2 is NOT yet complete:** the 21 newly accepted variation seeds (324
seeds now) brought follow-on derivative units into the registry — at 04:00:
+8 variation, +31 fim, +326 test-fim. The loop was relaunched with the same
idempotent command to converge; a monitor re-arms on its PID. Repeat until
`mix run scripts/work_status.exs --counts` shows 0 pending everywhere (each
new variation seed spawns its own derivatives, so expect one or two more
passes). If the loop is dead with pending work, relaunch:
`GEN_ONLY=backfill scripts/run_detached.sh logs/backfill_phase2.log mix run scripts/generate.exs`

Still waiting on Kamil (unchanged): the nightly-sweep systemd timer install
(§4.1.10, 4 commands in `scripts/systemd/nightly-sweep.service`) and the
§4.2 / §5.2 decisions.

---

## The two modes (definitions)

**STEADY STATE** — one command produces new data
(`scripts/run_detached.sh logs/loop.log mix run scripts/generate.exs`), every
quality check lives inside that loop or in CI, and nothing needs to be "caught
up". No backfill tooling exists in the repository.

**CATCHING UP (improvement round #N)** — we raised the quality standard, so
existing data must be brought up to it. Every round follows the protocol in
docs/12 §7.3: bump the standard → wire the new check into the loop + CI *first*
→ write a one-shot upgrade tool with its own ledger → run it to completion →
verify the whole corpus → **delete the tool** → flip this file back.

## Round history

| # | Round | Dates | What was raised | Status |
|---|-------|-------|-----------------|--------|
| 1 | 2026-07 QA catch-up | 2026-07-07 → … | prompt↔test consistency, mutation & format gates, embed staleness, blind screening (docs/10) | **in progress** |
