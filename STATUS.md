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

**PUSH of the remint batch (detached, log `logs/push_v3_20260717.log`;
a second push follows for the part-2 repair commit), then: the
NEEDS-TRIAGE JUDGE SWEEP — no new tool needed.** Discovery 2026-07-17:
the standing `scripts/triage_screen.exs` (docs/10 R12d) already covers
BOTH triage queues in one pass — it judges every task whose LATEST
screen row is RED, and (a) each of the 94 audit needs_triage cycles left
exactly such a red row (the failed blind solve of its grown-and-discarded
harness, failing assertion captured in the row), and (b) the 25
re-screen reds are latest-red too. ~119 judge calls; ledger
`logs/screen_triage.jsonl` keyed (task, prompt sha), skip-if-triaged,
resumable. ENTAILED → hard-keep evidence; NOT entailed → judge proposes
the one missing prompt sentence (human applies — never automatic; T2.6
material). Rule 9 pilot DONE (3/3 verdicts reviewed in detail, all correctly
grounded: 003_003 + 005_004 prompt gaps with concrete proposed
sentences, 015_001 entailed keep with lifecycle-rule quotes). FULL
SWEEP now RUNNING — idempotent relaunch:
`scripts/run_detached.sh logs/triage_reds.log mix run scripts/triage_screen.exs`
On exit: `mix run scripts/triage_screen.exs -- --report`, then rule 7
on the classes — prompt gaps go to Kamil for sign-off (prompt edits
cascade, docs/10 invariant #5; each applied edit → sha-keyed re-screen);
keeps get their evidence rows and unblock T2.6 scoping. NOTE: no mix
runs while the sweep lives.

**NEW TRIAGE QUEUE from the re-screen: 25 of 50 roots came back RED
(quarantined, "prompt under-specified OR solver too weak"; rows in
`logs/screen_blind.jsonl`, red details in `logs/rescreen_stale.log`).**
Run the standing judge flow (`scripts/triage_screen.exs`, docs/10 R12d)
after the push; keeps get evidence rows, prompt-gap reds join the T2.6
material. Rule 7 applies per class.

**Flag for Kamil:** `tasks/077_002_deletable_interval_tree_02` was
DELETED (git rm, recoverable): its blanked fn `rebalance` no longer
exists after the audit's balancing redesign. Re-carve when convenient.

⚠️ Standing hazard until check_embeds (step 5) is green: children lag the
audit-edited roots — a nightly sweep firing mid-cascade can report false
flakes on those families, and DO NOT push (CI embed gate would fail).

---

## 📋 TODO (rules 7–10 apply: every finding = Task A fix data + Task B gate
the generator; pilots before full runs; one solved item = one commit)

### 1. T1.11 CASCADE — propagate the finished retro audit (top priority)

Audit output on disk, uncommitted: 228 `test_harness.exs` + 40
`solution.ex` rewritten. Ledger `logs/retro_audit.jsonl` (sha+gate keyed);
the cascade instructions are verbatim at the tail of
`logs/retro_audit_full.log`. In order:

1. ~~Embed resyncs + check_embeds~~ DONE GREEN 2026-07-17 (docs/15).
2. ~~Bugfix-pair invalidation + remint + six-property verification~~
   DONE 2026-07-17 (docs/15; commits per tool step, not per family —
   Kamil's 07-17 "commit on the way" directive).
3. **Two stray dirs** minted in the audit's pre-restart first hour
   (untracked, full triplets, no ledger row):
   `tasks/repair_001_002_fixed_window_counter_01_audit_00/` and
   `tasks/repair_001_003_hierarchical_limiter_01_audit_00/`. New
   evidence 07-17: mint_repairs counts both among its `exists` skips —
   same standing flow, first two mints. Still Kamil's call: verify +
   commit like the other 68, or delete + let the flow re-mint. The
   restarted audit minted no others — decide: verify + keep like any
   repair pair, or delete.

### 2. T1.11 TRIAGE — the 94 needs_triage roots (T2.6 prompt material)

Roots the audit refused to auto-change (verified untouched on disk). List:
`jq -r 'select(.outcome=="needs_triage")|.task' logs/retro_audit.jsonl | sort -u`
minus 001_002 (resolved to changed after the restart). Shape: ~80 "grown
harness not blind-solvable: <test>: <failure>" — the promise audit grew a
test an independent solver can't pass from the prompt alone; each is
either a prompt gap (T2.6 material), a bad grown test (drop), or a real
hard-task keep — plus ~15 staging compile errors. Rule 7 applies to every
class found here.

### 🔎 OPEN FINDINGS

**T1.6 Task-A queue — 8 machine-proven spec lies (dialyzer gate,
2026-07-16; Task B = the standing weekly-CI gate, so each item closes when
its data fix lands). Was deferred on the running retro audit — now
UNBLOCKED; do after the cascade (queue below). Each fix: edit the spec →
re-run the gate → full cascade (embeds resync + reminted bugfix pairs):**

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

### ⏭️ QUEUE ORDER (after items 1–2 above)

1. T1.6 Task-A queue (the 8 findings above) + one dialyzer re-pass —
   audit-edited golds have fresh shas (40 solutions changed), so the
   pass re-verifies them all; relaunch:
   `scripts/run_detached.sh logs/dialyzer_golds_full.log bash -c "cd
   /home/kamil/projects/elixir-sft-dataset-t16 && nice -n10 mix run
   scripts/dialyzer_golds.exs -- --tasks
   /home/kamil/projects/elixir-sft-dataset/tasks --ledger
   /home/kamil/projects/elixir-sft-dataset/logs/dialyzer_golds.jsonl"`.
2. §4.2.2 spot-review tranche: ~20 April-era seeds stratified against the
   sweep ledger toward audit-clean roots (doubles as the T2.2 residue
   check; signed off 2026-07-16).
3. T2.6 prompt-precision tool (same skeleton as retro_audit.exs; feed it
   the 94 triage rows from item 2) — never concurrently with the sweep.

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
