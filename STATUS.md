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
      longer blocked by them); OPEN: §5.1 item 8 (module-FIM/wt embed gate),
      §5.2 decision (accept-time blind screen for repaired bases + entailment
      judge)
- [ ] Phase 2: derivative top-up run complete (work_status shows 0 pending everywhere)
- [ ] Phase 3: new generation resumed and first batch validated
- [ ] The line: catch-up tooling deleted per docs/12 §7.2, this file flipped

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
