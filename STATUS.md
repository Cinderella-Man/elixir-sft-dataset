# PROJECT STATUS — the live work list (read after CONTEXT.md's HOW-WE-WORK rules)

**HARD RULE (CONTEXT.md rule 5): this file contains ONLY todo / in-progress /
blocked items — NOTHING that is done.** Completed work moves immediately to
`docs/15-completed-work-log.md` (and lives in git history). Update it AS YOU
GO — before launching a job, after finishing one — never "at the end".

Reference docs: `docs/14` (handover: gates, tools, ledgers, runbooks),
`docs/12` (quality standard; §7 = the two modes + round protocol),
`docs/13` (data-extension designs), `docs/15` (everything finished).

---

## ▶️ RUNNING RIGHT NOW

**T1.11 FULL RETRO-AUDIT — pid 3468644, log `logs/retro_audit_full.log`,
ledger `logs/retro_audit.jsonl` (sha+gate keyed, fully resumable).**
Idempotent relaunch:
`scripts/run_detached.sh logs/retro_audit_full.log mix run scripts/retro_audit.exs`
~300 of 326 roots to go; wall-clock is dominated by token windows (expect
days, not hours). AFTER the run: follow the log's cascade instructions
(resyncs + `audit_bugfix` on solution-changed families + remint invalidated
pairs via `generate.exs <n>`), triage the `needs_triage` ledger rows (T2.6
prompt material), commit per family batch.

*(Only the retro audit is running. Standing constraint while it lives:
NEVER `mix compile` in this tree — CPU work runs from the
`../elixir-sft-dataset-t16` worktree.)*

---

## 📋 TODO (rules 7–10 apply: every finding = Task A fix data + Task B gate
the generator; pilots before full runs; one solved item = one commit)

### 🔎 OPEN FINDINGS

**T1.6 Task-A queue — 8 machine-proven spec lies (dialyzer gate,
2026-07-16; Task B = the standing weekly-CI gate, so each item closes when
its data fix lands). DEFERRED until the retro audit finishes: gold edits
race its writes, and the bugfix-remint cascade costs LLM. Each fix: edit
the spec → re-run the gate → full cascade (embeds resync + reminted bugfix
pairs):**

- **F20 — 015_001**: `@typep service` omits the `timer: reference()` field
  the 07-15 F12 repair added (runtime-safe, but the type lies; a spec lie
  introduced BY a repair, caught next day).
- **F21 — 102_002**: migration `change/0` spec'd `:: :ok` but returns
  Ecto's DSL value — "return types do not overlap"; check sibling
  migrations while there.
- **032_002**: `parse_csv/1` returns a `{headers, rows}` tuple; spec says
  list of tuples.
- **044_004 / 077_004 / 100_002 / 625_003**: arithmetic can produce
  `float()` where specs promise integer types (`rate/2`+`count/1`,
  `prefix_sum/2`, `seconds_remaining/2`+`base32_value/1`,
  `compute_expires_at/2`).
- **073_003**: `ensure_registry/0` can return `{:error, _}`; spec admits
  only `{:ok, pid()}`.

Fold-in for the cutover checklist (docs/12 §5.5): repairs must re-run the
spec gate on the repaired file — F20 is the proof it's needed.

### 🔨 BUILDS

**In-loop quarantine-triage path** (docs/17 §6.3): the loop can quarantine
but has no "hard-task KEEP" verdict (the retro screen had 49 keeps).
Phase 3 needs: triage judge over `logs/quarantine/*` + Kamil review + a
keep-promotion path writing the evidence row. Until built, quarantines
block their idea and surface here.

**T1.4 sliver (d)**: record each seed's blind-screen outcome as difficulty
metadata (ledger-side, tiny — fold into the export work).

### ⏭️ QUEUED AFTER THE RETRO AUDIT (in order)

1. The audit's cascade + `needs_triage` triage (see RUNNING).
2. T1.6 Task-A queue (findings above) + one dialyzer re-pass
   (audit-edited golds get fresh shas; relaunch:
   `scripts/run_detached.sh logs/dialyzer_golds_full.log bash -c "cd
   /home/kamil/projects/elixir-sft-dataset-t16 && nice -n10 mix run
   scripts/dialyzer_golds.exs -- --tasks
   /home/kamil/projects/elixir-sft-dataset/tasks --ledger
   /home/kamil/projects/elixir-sft-dataset/logs/dialyzer_golds.jsonl"`).
3. §4.2.2 spot-review tranche: ~20 April-era seeds stratified against the
   sweep ledger toward audit-clean roots (doubles as the T2.2 residue
   check; signed off 2026-07-16).
4. T2.6 prompt-precision tool (same skeleton as retro_audit.exs) — never
   concurrently with the sweep.

### 📦 DATA EXTENSION (docs/13 §2; after the above)

- **T2.6 proper — prompt-register monotony rewrite** (improvement round
  #2 — NOT before steady state) [BIG: 2,396 tfim + 302 wt_ + 80/332 seed
  openers; own tool + ledger + blind re-screen budget] — docs/12 §7.4.
- **TD.2 — multi-turn repair-dialogue exporter** (PERISHABLE raw material —
  snapshot `logs/attempts/` before any big run; archives 2026-07-12 and
  2026-07-14b; 745 chains / 100 mintable rejected→accepted pairs). §2.2.
- **TD.3 — dedoc (~331 free units)** — unblocked once the T1.6 pass reads
  all-clean after the Task-A fixes. §2.3.
- **TD.4 — style-repair pairs (207) + cap lifts (~1,900 free tfim)** —
  weigh against docs/16 §4's advisory weights. §2.4–2.5.

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
