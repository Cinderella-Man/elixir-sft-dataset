#!/usr/bin/env bash
# spot_verify.sh — ONE-SHOT random re-verification of ACCEPTED corpus data
# (Kamil, 2026-07-13: "scrutinize everything, do random verifies of approved
# and rejected data — there could be errors in the scripts"). The rejected-side
# twin is scripts/reverify_rejects.exs.
#
# Draws a DETERMINISTIC random sample per shape (fixed shuf seed, so re-runs
# verify the same dirs) and re-runs the REAL gates over it:
#   numbered dirs (roots + fim)  → validate perfect, then --mutants, then --fim
#   wt_                          → validate perfect + --mutants
#   tfim_                        → validate perfect
#   repair_ (all 17)             → validate perfect
#   bugfix_                      → audit_bugfix (six-property rebuild)
#
# Ledger: logs/spot_verify.jsonl — one row per batch; a batch with ok=true is
# skipped on re-run, so the driver is resumable. Per-batch console output goes
# to logs/spot_verify_<batch>.log (the evidence when ok=false).
#
# Families currently being written by the quality chain (strengthen stage) are
# EXCLUDED from sampling: 063_004*, 101_001*.
#
# Launch:  scripts/run_detached.sh logs/spot_verify_20260713.log scripts/spot_verify.sh
set -u
cd "$(dirname "$0")/.." || exit 1

LEDGER=logs/spot_verify.jsonl
SEED_STREAM() { yes 20260713; }   # fixed --random-source => deterministic sample
EXCLUDE='063_004|101_001'
export EVAL_CONCURRENCY="${EVAL_CONCURRENCY:-8}"   # leave headroom for the chain

done_ok() { grep -q "\"batch\":\"$1\",\"ok\":true" "$LEDGER" 2>/dev/null; }

record() { # batch ok n
  printf '{"batch":"%s","ok":%s,"n":%s,"ts":"%s"}\n' "$1" "$2" "$3" "$(date -Is)" >>"$LEDGER"
}

sample() { # pattern n
  ls -d $1 2>/dev/null | sed 's|tasks/||' | grep -Ev "$EXCLUDE" | sort \
    | shuf -n "$2" --random-source=<(SEED_STREAM)
}

run_batch() { # batch dirs_csv cmd...
  local batch="$1" dirs="$2" log="logs/spot_verify_$1.log"; shift 2
  if done_ok "$batch"; then echo "[skip] $batch already ok"; return 0; fi
  local n; n=$(awk -F, '{print NF}' <<<"$dirs")
  echo "[run ] $batch (n=$n) -> $log"
  if "$@" --only "$dirs" >"$log" 2>&1; then
    record "$batch" true "$n"; echo "[ ok ] $batch"
  else
    record "$batch" false "$n"; echo "[FAIL] $batch — see $log"
  fi
}

echo "=== spot_verify start $(date -Is)"

NUMBERED=$(sample 'tasks/[0-9]*' 45 | paste -sd,)
WT=$(sample 'tasks/wt_*' 12 | paste -sd,)
TFIM=$(sample 'tasks/tfim_*' 25 | paste -sd,)
REPAIR=$(ls -d tasks/repair_* | sed 's|tasks/||' | paste -sd,)

run_batch numbered_perfect "$NUMBERED" elixir scripts/validate.exs
run_batch numbered_mutants "$NUMBERED" elixir scripts/validate.exs --mutants
run_batch numbered_fim     "$NUMBERED" elixir scripts/validate.exs --fim
run_batch wt_perfect       "$WT"       elixir scripts/validate.exs
run_batch wt_mutants       "$WT"       elixir scripts/validate.exs --mutants
run_batch tfim_perfect     "$TFIM"     elixir scripts/validate.exs
run_batch repair_perfect   "$REPAIR"   elixir scripts/validate.exs

# bugfix: audit_bugfix takes dir names as argv, not --only
if done_ok bugfix_audit; then
  echo "[skip] bugfix_audit already ok"
else
  BUGFIX=$(sample 'tasks/bugfix_*' 25)
  n=$(wc -l <<<"$BUGFIX")
  echo "[run ] bugfix_audit (n=$n) -> logs/spot_verify_bugfix_audit.log"
  if mix run scripts/audit_bugfix.exs $BUGFIX >logs/spot_verify_bugfix_audit.log 2>&1 \
     && grep -q "^$n/$n accepted units verified" logs/spot_verify_bugfix_audit.log; then
    record bugfix_audit true "$n"; echo "[ ok ] bugfix_audit"
  else
    record bugfix_audit false "$n"; echo "[FAIL] bugfix_audit — see logs/spot_verify_bugfix_audit.log"
  fi
fi

echo "=== spot_verify done $(date -Is)"
grep -c '"ok":true' "$LEDGER" 2>/dev/null | xargs -I{} echo "batches ok so far: {}"
