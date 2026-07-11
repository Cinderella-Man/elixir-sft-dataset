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
- [ ] docs/12 §5 loop hardening — §5.1 items 1–7 DONE 2026-07-10 (Phase 3 no
      longer blocked by them); §5.1 item 8 (module-FIM/wt embed gate) is
      **nearly done, paused mid-classification 2026-07-11** — see "Where we
      are right now" below for exact state + resume steps; OPEN: §5.2 decision
      (accept-time blind screen for repaired bases + entailment judge)
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

**2. docs/12 §5.1 item 8 (embed staleness gate) — checker committed,
classification being finished in small batches.** State:

- `scripts/check_embeds.exs` (committed) checks every module-FIM child
  and `wt_` dir embed against its parent `_01/solution.ex`. Ignore rules are
  the named conventions a–f documented in its header; format check and the
  planted-phantom self-test are green. Corpus numbers as of today:
  **933 clean, 162 reflow, 156 drift, 0 skipped** (from 461 raw drift before
  the rules). "Reflow" = content identical but line-wrapping stale (the
  2026-07 format canonicalization rewrapped parents; these embeds need a
  mechanical resync, not investigation). Dir lists + full report backed up in
  `logs/embed_check_backup/` (regenerable any time by re-running the script —
  deterministic, no LLM cost).
- The classification workflow (one Opus reader per family) died with its
  session on 2026-07-11; its cache is session-bound and NOT resumable from a
  new session. **All 55 completed family classifications were recovered from
  the workflow journal** into `logs/embed_classify/recovered.jsonl` (durable,
  ledger-style; logs/ is gitignored by convention — the committable artifact
  is the final docs/12 report). Recovered verdict tally over 134 of 156 drift
  dirs: 108 real_drift (97 resync_embed + 11 fix_child_gold), 14 claimed
  missed_convention, 12 claimed checker_bug.
- Remaining work, done in SMALL batches (append to the ledger after every
  batch, commit at every iteration boundary — no big fan-outs):
  (a) classify the last 9 families — fam_038, 039, 050, 054, 056, 057, 059,
  062, 063 (22 dirs; briefs in `logs/embed_check_backup/fams/`), one Opus
  agent per family, batches of ~5;
  (b) the 26 non-drift claims are verified DETERMINISTICALLY instead of by
  refuter agents: implement each accepted rule/fix in `check_embeds.exs`,
  re-run, confirm exactly the claimed dirs clear while the planted-phantom
  self-test stays red; rules judged over-broad are rejected and their dirs
  reclassified as real_drift.
- After classification lands: fold confirmed conventions into the checker,
  re-run for final numbers, update docs/12 §5.1 item 8 + this file, commit
  (no push without Kamil's word). The 12 families whose child gold could not
  be located in the parent are the prime suspects for real parent-redesign
  drift.
- Follow-up decision to queue for Kamil: remediation of the 162 reflow dirs +
  whatever classification confirms as stale-embed drift — likely a
  `resync_embeds.exs` in the spirit of `resync_tfim_embeds.exs`, run only
  after Phase 2 finishes (it rewrites existing `prompt.md` files; don't do
  that under a live loop).

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
