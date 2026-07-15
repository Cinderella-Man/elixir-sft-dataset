#!/usr/bin/env bash
# nightly_sweep.sh — unattended full-corpus sweep for flake accumulation (docs/10 R9).
#
# Intended to run from cron on a dedicated machine (NOT necessarily a dev box) —
# see README "Nightly flake sweep" for the cron setup. No LLM calls are made;
# this is pure CPU work (~15 min on 16 cores).
#
# What it does, in order:
#   1. mix compile          — scripts prepend _build ebin; stale beams run old logic
#   2. validate --stability 3  — full perfect-score sweep; a test-failure suspect
#      must pass 3 consecutive serial re-runs to recover. Every recovery appends a
#      ledger entry to logs/flaky.jsonl WITH the failing test name + message.
#   3. prints the ledger's repeat-offender aggregation — ≥2 occurrences of the
#      same task (stronger: the same test) is the R9 threshold for fixing.
#
# Exit code: 0 when the sweep is ALL PERFECT (recovered flakes still pass),
# non-zero on any hard failure — wire cron mail / monitoring to it.
set -euo pipefail
cd "$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"

# Detached-job guard (2026-07-16). Every scripts/run_detached.sh job (retro
# audit, generation loop, LLM sweeps) records `pid=<N> cmd=<...>` lines in a
# logs/<name>.pid sidecar and can legally be alive for DAYS (the transport
# sleeps out token windows). Sweeping under one is not safe: `mix compile`
# rewrites _build beams that the job's bare-elixir graders load mid-flight,
# and a full-corpus grading sweep alongside its evals turns CPU contention
# into false flake-ledger rows. Skip (exit 0 — a skip, not a failure) while
# any recorded job is still alive; Persistent=true retries tomorrow.
for pidfile in logs/*.pid; do
  [ -e "$pidfile" ] || continue
  line=$(tail -n 1 "$pidfile")
  pid=$(printf '%s' "$line" | sed -nE 's/.*pid=([0-9]+).*/\1/p')
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || continue
  # Recycled-pid check: trust the pid only if the live process's cmdline
  # still contains the recorded script path. A job whose cmd carries no
  # scripts/ token (e.g. bash -c wrappers) is treated as alive — the
  # conservative direction for a gate.
  script=$(printf '%s' "$line" | grep -oE 'scripts/[A-Za-z0-9_./-]+' | head -1 || true)
  if [ -z "$script" ] || tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -qF "$script"; then
    echo "SKIP nightly sweep: detached job alive (pid $pid — $pidfile: $line)"
    exit 0
  fi
done

mkdir -p logs/nightly
log="logs/nightly/sweep_$(date +%Y%m%d_%H%M%S).log"

{
  echo "=== nightly sweep $(date -Is) — $(git rev-parse --short HEAD) ==="
  mix compile --warnings-as-errors
  elixir scripts/validate.exs --stability 3

  echo
  echo "=== flake ledger: occurrences per task ==="
  jq -r .task logs/flaky.jsonl 2>/dev/null | sort | uniq -c | sort -rn || echo "(no ledger yet)"
  echo
  echo "=== flake ledger: occurrences per test (entries since 2026-07-09) ==="
  jq -r '"\(.task) :: \(.failures[]?.test // "?")"' logs/flaky.jsonl 2>/dev/null |
    sort | uniq -c | sort -rn | head -20 || true
} 2>&1 | tee "$log"

# Keep the last 30 nightly logs.
ls -1t logs/nightly/sweep_*.log 2>/dev/null | tail -n +31 | xargs -r rm --
