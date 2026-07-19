# PROJECT STATUS — the live work list (read after CONTEXT.md's HOW-WE-WORK rules)

**HARD RULE (CONTEXT.md rule 5): this file contains ONLY todo / in-progress /
blocked items — NOTHING that is done.** Completed work moves immediately to
`docs/15-completed-work-log.md` (and lives in git history). Update it AS YOU
GO — before launching a job, after finishing one — never "at the end".

Reference docs: `docs/14` (handover: gates, tools, ledgers, runbooks),
`docs/12` (quality standard; §7 = the two modes + round protocol),
`docs/13` (data-extension designs), `docs/15` (everything finished).

---

## 📋 TODO (rules 7–10 apply: every finding = Task A fix data + Task B gate
the generator; pilots before full runs; one solved item = one commit)

### ▶️ DAY SESSION 2026-07-19 (Kamil, ~09:30: "finish everything besides
### new task generation"; two directed decisions: 110_002 APPROVE, and
### UNPARK all three derivation builds — spec-fim, TDD-inverse,
### bundle-v2; T2.6-proper stays round #2 per the 07-16 sign-off).
### Work queue (items 1-4 + the CI red DONE — docs/15 morning entry;
### build order corrected by integration-cost investigation):
### 5. TDD-inverse — DONE 10:30 (326 units, 100% yield, all validated;
###    docs/15). Export refreshed to 12,792.
### 6. spec-fim — SHAPE BUILT + pilot green (ddaea7c0); FULL MINT
###    RUNNING detached (logs/specfim_mint.log, ~2,570 sites, 2 evals
###    each). On exit: validate specfim_*, spot-reads, export refresh,
###    commit+push.
### 7. bundle-FIM (6 bundles) — Runner.run_fim_bundle + reconstruct_bundle
###    ALREADY EXIST (tested); build = a small miner carving one file per
###    hole into the existing :fim shape.
### 8. LOOP DERIVATION COMPLETENESS — ALL CODE WRITTEN 11:20, pending
###    compile+pilot behind the running specfim mint (no mix while it
###    holds _build). What landed on disk: 4 Work-registry entries
###    (sfim/tdd/specfim/bundlefim) + Config GEN_SKIP_* flags +
###    GenTask.DeriveMiners (loads the guarded miner scripts — script
###    stays the single implementation) + scripts/derive_family.exs
###    (manual one-command family derivation over the same registry) +
###    bundle-FIM shape (BundleFimTemplate + mint_bundlefim.exs +
###    resync_bundlefim_embeds.exs + hook/CI wiring + format_corpus
###    template-split generalized + docs/16 rows).
###    POST-MINT CHECKLIST (run IN ORDER when logs/specfim_mint.log
###    exits): (a) mix format new files; compile --warnings-as-errors;
###    mix test. (b) validate --only "specfim_*" + 3 spot-reads +
###    resync_specfim dry-run (corpus-wide unchanged = derivation
###    identity). (c) bundlefim: pilot --limit 3 → detailed read → full
###    run → self-test + dry-run → check_embeds + format gate.
###    (d) work_status matrix shows 4 new rows; derive_family --dry-run
###    on 2 families reports all-complete (idempotency + full-coverage
###    proof). (e) export refresh + README + docs/15 + commits + push.
### 9. Close: full-corpus sweep (perfect+fim+mutants), decontam, export/
###    README/docs-15 refresh, push.

**Standing decision (Kamil):** the strategic fork — Phase 3 (490 queued
bases; ~57/1000 ideas realized is the binding constraint) vs a
training/eval cycle on the export (converts the parked questions —
register monotony, shape weights, difficulty curve, T2.6-proper's worth
— into measurements).

**Phase E — the honest fork (Kamil; roadmap Phases A–D all done, see
docs/15):** after C, existing-corpus
derivation is ESSENTIALLY EXHAUSTED. Remaining upside: (a) Phase 3 —
base-idea diversity (57 of ~1000 ideas realized) is the binding
constraint no derivation fixes; or (b) run a training/eval cycle on the
export and let its results (register monotony? shape mix? difficulty
curve?) decide the next data work — incl. whether T2.6-proper's big
register rewrite is worth its LLM budget. PARKED until then:
T2.6-proper, spec-fim (1,869 sites), TDD-inverse, bundle-v2 coverage
(6 dirs), keep-packet approvals (Kamil, any time).

---

## Current mode: 🔧 CATCHING UP (improvement round #1, 2026-07)

New base generation is **paused**. Mode definitions + round protocol:
docs/12 §7; round history + everything finished: docs/15. Remaining exit
conditions:

- [ ] **LOOP PARITY (docs/12 §5.5)**: every row of the parity table reads
      ENFORCED or is explicitly waived by Kamil.
- [ ] Phase 3: new generation resumed (490 queued bases) and the first
      batch passes the **cutover acceptance test** (docs/12 §5.5 bottom):
      full semantic_review of every new root + a rubric_judge two-family
      pass + all sweeps — ZERO triage-grade findings, else stop and fix
      the GENERATOR, never the data.
- [ ] The line drawn (docs/12 §7.2): delete catch-up tooling per the §7.2
      + docs/14 disposition tables (the four resync DRIFT GATES and the
      standing audits stay), remove the backfill vocabulary, delete the
      `../elixir-sft-dataset-t16` worktree, flip this file to STEADY STATE.
