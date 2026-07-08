#!/usr/bin/env bash
# run_detached.sh — launch a long-running command immune to the parent session dying.
#
# LLM sweeps (screen_blind_solve.exs, generate.exs) routinely outlive the terminal /
# Claude Code session that started them: the transport rides out token-allowance
# windows by sleeping 15 min per attempt (see GenTask.Opus), so a sweep can legally
# sit idle for hours. If it runs as a foreground child, dropping the session KILLS
# it mid-wait (this happened on 2026-07-08 during the R12a re-screen). setsid gives
# it its own session so no SIGHUP reaches it; nohup + full redirection detach it
# from the terminal entirely.
#
# Usage:
#   scripts/run_detached.sh <logfile> <command> [args...]
#   scripts/run_detached.sh logs/rescreen.log mix run scripts/screen_blind_solve.exs --only "024_004*"
#
# Prints the detached PID. Follow progress with:  tail -f <logfile>
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <logfile> <command> [args...]" >&2
  exit 2
fi

log="$1"
shift
mkdir -p "$(dirname "$log")"

setsid nohup "$@" >>"$log" 2>&1 </dev/null &
pid=$!
echo "detached: pid=$pid log=$log"
echo "$(date -Is) pid=$pid cmd=$*" >>"${log%.log}.pid"
