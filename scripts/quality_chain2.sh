#!/usr/bin/env bash
# quality_chain2.sh — ONE-SHOT catch-up driver #2 (delete at the line, docs/12 §7.2).
# Stateless like quality_chain.sh: every tool resumes from its content-keyed
# ledger, so relaunching after any death is idempotent. Launch ONLY via:
#
#   scripts/run_detached.sh logs/quality_chain2_20260713.log scripts/quality_chain2.sh
#
# Stages:
#   1  re-screen 013_001 (--rescreen): its harness was hand-strengthened; the
#      blind property must be re-proven against the STRONGER harness (~1 call)
#   2  screen the 4 prompt-gap fixes (102_002/3/4 migration-module name,
#      626_004 :cleanup_tick) — new shas are ledger misses (~4 calls)
#   3  entailment-judge triage of the 6 remaining RED repaired accepts
#      (022_004, 100_002/3/4, 101_003, 624_002) (~6 calls)
#   4  strengthen retry #3 for 101_001 (stochastic; S9 lint rejected the
#      first two attempts) (~2 calls)
#   5  FREE backfill: mints the re-opened 102_001 tfim units + new carvable
#      blocks from the strengthened 013_001/063_004 harnesses (0 LLM for tfim)
#   6  report-only: registry counts + all four embed gates (dry) + format
set -u
cd "$(dirname "$0")/.." || exit 1

stamp() { echo "=== [chain2] $* — $(date -Is)"; }

stamp "stage 1: re-screen 013_001 against the strengthened harness"
mix run scripts/screen_blind_solve.exs --only "013_001*" --rescreen
stamp "stage 1 exit=$?"

stamp "stage 2: screen the 4 prompt-gap fixes"
mix run scripts/screen_blind_solve.exs --only "102_002_optimistic*,102_003_auto*,102_004_threshold*,626_004*"
stamp "stage 2 exit=$?"

stamp "stage 3: entailment triage of the 6 remaining REDs"
mix run scripts/triage_screen.exs --only "022_004*,100_002*,100_003*,100_004*,101_003*,624_002*"
stamp "stage 3 exit=$?"

stamp "stage 4: strengthen retry for 101_001"
mix run scripts/strengthen_harnesses.exs -- --go --only "101_001*"
stamp "stage 4 exit=$?"

stamp "stage 5: free backfill (re-opened + new-carvable units)"
GEN_ONLY=backfill mix run scripts/generate.exs
stamp "stage 5 exit=$?"

stamp "stage 6: report-only verification"
mix run scripts/work_status.exs --counts
mix run scripts/resync_tfim_embeds.exs | tail -1
mix run scripts/resync_bugfix_embeds.exs | tail -1
mix run scripts/resync_embeds.exs -- --wt-all | tail -1
elixir scripts/check_embeds.exs | tail -1
elixir scripts/format_corpus.exs --check | tail -1
mix run scripts/rescreen_repaired.exs -- --report

stamp "CHAIN2 DONE"
