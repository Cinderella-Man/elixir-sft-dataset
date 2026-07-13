#!/usr/bin/env bash
# quality_chain.sh — ONE-SHOT catch-up driver (delete at the line, docs/12 §7.2).
#
# Runs the 2026-07-13 paid quality chain sequentially. The driver itself is
# STATELESS: every tool below keeps its own content-keyed ledger and skips
# finished work, so relaunching this script after any death (token exhaustion,
# reboot, kill) resumes exactly where it stopped. Launch ONLY via:
#
#   scripts/run_detached.sh logs/quality_chain_20260713.log scripts/quality_chain.sh
#
# Stages (docs/14 §5.1 item 1 + §5.3 real gaps):
#   1  rescreen_repaired --go        — retro S6 screen of the 22 never-screened
#                                      repaired accepts (~22 solver calls)
#   2  enrich_prompts 063_004 --force— document zero-budget timeout semantics
#   2b screen_blind_solve 063_004    — canonical S6 row for the NEW sha only
#                                      (no --rescreen: if enrich failed, the old
#                                      sha is cached and this costs nothing)
#   3  strengthen 063_004 + 101_001  — targeted; NOT the at-ceiling trio
#                                      (041_001/041_003/023_002) and NOT
#                                      077_001/013_001 (hand-work, docs/14 §5.3)
#
# A stage failure does NOT abort the chain (stages are independent except
# 2→2b→3-for-063_004, where a miss surfaces as a ledgered reject, not damage:
# strengthen restores the original harness on any gate failure).
set -u
cd "$(dirname "$0")/.." || exit 1

stamp() { echo "=== [chain] $* — $(date -Is)"; }

stamp "stage 1: rescreen repaired accepts (~22 calls)"
mix run scripts/rescreen_repaired.exs -- --go
stamp "stage 1 exit=$?"
mix run scripts/rescreen_repaired.exs -- --report

stamp "stage 2: enrich 063_004 (--force, zero-budget semantics)"
mix run scripts/enrich_prompts.exs -- --go --force --only "063_004*"
stamp "stage 2 exit=$?"

stamp "stage 2b: canonical S6 screen of 063_004 (new sha only)"
mix run scripts/screen_blind_solve.exs --only "063_004*"
stamp "stage 2b exit=$?"

stamp "stage 3: strengthen 063_004 + 101_001 (targeted)"
mix run scripts/strengthen_harnesses.exs -- --go --only "063_004*,101_001*"
stamp "stage 3 exit=$?"
mix run scripts/strengthen_harnesses.exs -- --report

stamp "CHAIN DONE"
