# PROJECT STATUS — the live work list (read after CONTEXT.md's HOW-WE-WORK rules)

**HARD RULE (CONTEXT.md rule 5): this file contains ONLY todo / in-progress /
blocked items — NOTHING that is done.** Completed work moves immediately to
`docs/15-completed-work-log.md` (and lives in git history). Update it AS YOU
GO — before launching a job, after finishing one — never "at the end".

Reference docs: `docs/14` (handover: gates, tools, ledgers, runbooks),
`docs/12` (quality standard; §7 = the two modes + round protocol),
`docs/13` (data-extension designs), `docs/15` (everything finished).

---

## ▶️ IN PROGRESS THIS SESSION (2026-07-18)

**T2.6 PRECISION FULL RUN FINISHED** — summary
`%{unchanged: 156, improved: 151, needs_triage: 17}` (ledger totals incl.
3 pilot roots: 152/158/17). Process exited; log `logs/precision_full.log`;
ledger `logs/prompt_precision.jsonl`. Post-run work, in order:

- [ ] **Triage the 17 needs_triage roots** (prompts on disk are UNTOUCHED —
      proposal discarded; 14 rejected candidates saved in
      `logs/prompt_precision_candidates/`, the 3 structural-vet fails have
      no saved candidate). Per root: diff candidate vs prompt, read the
      named failing test, check the root's standing blind-screen verdict;
      verdict one of: ORIGINAL-FINE (reject was correct) / HAND-FIX
      (real precision gap → rule-7 two-tier item) / RERUN (tool retry
      worth it). Checklist (verdict inline as each closes):
      - [ ] 007_001_moving_average_calculator_01 — blind RED: SMA different periods on same stream
      - [ ] 007_002_weightedmovingaverage_01 — blind RED: larger period grows max_period / retains history
      - [ ] 009_003_retry_aware_request_deduplicator_01 — blind RED: GenServer not blocked during retries
      - [ ] 012_001_event_sourced_aggregate_01 — blind RED: not green
      - [ ] 013_003_budget_constrained_retry_worker_with_decorrelated_jitter_01 — vet: dropped Process.send_after
      - [ ] 014_001_priority_queue_processor_01 — vet: dropped spawn_monitor/1
      - [ ] 024_002_replay_protected_timestamped_webhook_receiver_01 — blind RED: in-window signature stores event
      - [ ] 025_001_long_polling_endpoint_01 — blind RED: notification published mid-poll
      - [ ] 025_003_coalescing_batch_long_poll_with_linger_window_01 — blind RED: burst → one batched response
      - [ ] 041_003_sharded_lru_cache_with_consistent_key_routing_01 — blind RED: missing required option fails loudly
      - [ ] 044_001_ets_based_metrics_collector_01 — vet: dropped Metrics.increment/2
      - [ ] 045_001_ets_based_feature_flag_store_01 — blind RED: enable sets flag on for everyone
      - [ ] 061_001_parallel_map_with_concurrency_limit_01 — blind RED: never exceeds max_concurrency=3
      - [ ] 064_004_instrumented_work_stealing_queue_with_steal_metrics_01 — blind RED: default steal batch = half of victim's queue
      - [ ] 072_004_scripted_sequence_clock_01 — blind RED: :on_exhaust :raise blows up when script exhausted
      - [ ] 073_001_database_cleaner_for_integration_tests_01 — blind RED: failed transaction start/2 still replaces prior truncation state
      - [ ] 624_002_merge_commit_dag_with_topological_log_and_merge_base_01 — blind RED: log walks linear chain newest-to-oldest

Relaunch note: ledger rows are content+gate-sha keyed, so a relaunch of
`prompt_precision.exs` skips ALL 329 roots (incl. the 17 — their prompts
are unchanged, so their needs_triage rows still match). A per-root retry
requires a prompt/harness/tool change or a deliberate ledger-row removal.

---

## 📋 TODO (rules 7–10 apply: every finding = Task A fix data + Task B gate
the generator; pilots before full runs; one solved item = one commit)

### 🧑‍⚖️ WAITING ON KAMIL

**Two stray repair dirs** minted in the audit's pre-restart first hour
(untracked, full triplets, no ledger row):
`tasks/repair_001_002_fixed_window_counter_01_audit_00/` and
`tasks/repair_001_003_hierarchical_limiter_01_audit_00/`. Evidence
07-17: mint_repairs counts both among its `exists` skips — same standing
flow, first two mints. Call: verify + commit like the other 68, or
delete + let the flow re-mint.

### 🔎 OPEN FINDINGS

**Template-rule candidate (F22 Task B, for the Phase-3 template work):**
"for any input the prompt's own validation rules accept, the gold must
terminate promptly without crashing" — F22 is the proof; fold into the
T1.4 template rules alongside the LIFECYCLE RULE when next edited.

**~15 audit needs_triage rows are staging COMPILE errors** (the grown
harness never compiled, so no blind screen row exists and the 07-17
judge sweep could not cover them; the roots on disk are unaffected and
green). List:
`jq -r 'select(.outcome=="needs_triage") | select(.detail|contains("compile:")) | .task' logs/retro_audit.jsonl`
Triage: re-run the promise audit on these roots (`generate.exs <n>`
paths) or log them as auditor-bug evidence — rule 7 either way.

**Cutover-checklist fold-in still to land (docs/12 §5.5): repairs must
re-run the spec gate on the repaired file — F20 (a spec lie introduced
BY a repair) is the proof it's needed. Add the parity-table row when
docs/12 is next edited.**

### 🔨 BUILDS

**In-loop quarantine-triage path** (docs/17 §6.3): the loop can quarantine
but has no "hard-task KEEP" verdict (the retro screen had 49 keeps).
Phase 3 needs: triage judge over `logs/quarantine/*` + Kamil review + a
keep-promotion path writing the evidence row. Until built, quarantines
block their idea and surface here.

**T1.4 sliver (d)**: record each seed's blind-screen outcome as difficulty
metadata (ledger-side, tiny — fold into the export work).

### ⏭️ QUEUE ORDER

1. **T2.6 precision full run** — RUNNING (see above).

### 📦 DATA EXTENSION (docs/13 §2; after the above)

- **TD.3 — dedoc (~331 free units)** — NOW UNBLOCKED (T1.6 closed
  2026-07-17 with the pass reading clean-or-waived). §2.3.
- **T2.6 proper — prompt-register monotony rewrite** (improvement round
  #2 — NOT before steady state) [BIG: 2,396 tfim + 302 wt_ + 80/332 seed
  openers; own tool + ledger + blind re-screen budget] — docs/12 §7.4.
- **TD.2 — multi-turn repair-dialogue exporter** (PERISHABLE raw material —
  snapshot `logs/attempts/` before any big run; archives 2026-07-12 and
  2026-07-14b; 745 chains / 100 mintable rejected→accepted pairs). §2.2.
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
