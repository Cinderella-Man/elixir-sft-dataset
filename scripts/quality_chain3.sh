#!/usr/bin/env bash
# quality_chain3.sh — ONE-SHOT overnight driver (delete at the line, docs/12 §7.2).
# Stateless: every tool resumes from its ledger. Launch ONLY via:
#   scripts/run_detached.sh logs/quality_chain3_20260714.log scripts/quality_chain3.sh
# Stage 1: 100_004 strengthen retry #3 (two prior rejections were pure solver
#          defects — compile warning, non-compiling solve). ~2 calls.
# Stage 2: T2.3 — second-source the 14 FAIL-triaged-entailed keeps with one
#          fresh blind solve each (--rescreen; rows land harness_sha-stamped).
#          A new GREEN upgrades a keep to PASS; a RED confirms with 2 sources.
set -u
cd "$(dirname "$0")/.." || exit 1
stamp() { echo "=== [chain3] $* — $(date -Is)"; }

stamp "stage 1: strengthen retry 100_004"
mix run scripts/strengthen_harnesses.exs -- --go --only "100_004*"
stamp "stage 1 exit=$?"

stamp "stage 2: T2.3 second-source the 14 entailed keeps"
mix run scripts/screen_blind_solve.exs --only "022_004_invitation*,024_002_replay*,024_003_multi*,025_002_cursor*,036_002_hierarchical*,045_003_versioned*,045_004_dependency*,074_002_collection*,079_003_scalable*,100_002_provisioning*,100_003_counter*,100_004_stateful*,101_003_weighted*,624_002_merge*" --rescreen
stamp "stage 2 exit=$?"

mix run scripts/rescreen_repaired.exs -- --report
stamp "CHAIN3 DONE"
