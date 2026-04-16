#!/bin/bash
# Validates that all test harnesses compile correctly.
# Run this after adding new tasks to catch harness bugs.
#
# Usage: ./scripts/validate_harnesses.sh
#
# For each task, it:
#   1. Creates a minimal stub module that defines the expected functions
#   2. Compiles the stub + harness together
#   3. Reports any compilation errors in the HARNESS (not the stub)

set -uo pipefail

echo "Validating test harnesses..."
echo ""

TOTAL=0
OK=0
BROKEN=0

for TASK_DIR in tasks/*/; do
  [ ! -d "$TASK_DIR" ] && continue
  HARNESS="$TASK_DIR/test_harness.exs"
  [ ! -f "$HARNESS" ] && continue

  TOTAL=$((TOTAL + 1))
  TASK_NAME=$(basename "$TASK_DIR")

  # Try to compile just the test harness file with ExUnit loaded
  # This will fail if the harness references undefined modules,
  # but that's EXPECTED (the solution module isn't loaded).
  # We're checking for SYNTAX errors in the harness itself.

  TMP_ERR=$(mktemp)
  RESULT=$(elixir -e '
    # Suppress output
    ExUnit.start(autorun: false)
    try do
      Code.compile_file("'"$HARNESS"'")
      IO.puts("OK")
    rescue
      e in [SyntaxError, TokenMissingError] ->
        IO.puts("SYNTAX_ERROR: #{Exception.message(e)}")
      e in [CompileError] ->
        # CompileError can mean a missing module (OK) or a real harness bug.
        # Emit a distinct marker so we can inspect stderr to tell them apart.
        IO.puts("COMPILE_ERROR: #{Exception.message(e)}")
      e ->
        # UndefinedFunctionError or similar means the harness is fine
        # but the solution module is missing — this is expected
        if Exception.message(e) =~ "undefined" or
           Exception.message(e) =~ "UndefinedFunction" or
           inspect(e) =~ "UndefinedFunctionError" do
          IO.puts("OK_NEEDS_MODULE")
        else
          IO.puts("ERROR: #{Exception.message(e)}")
        end
    end
  ' 2>"$TMP_ERR")

  # A CompileError caused by a missing module (solution or library dep) is not
  # a harness bug — promote it to OK_NEEDS_MODULE.  Errors caused by genuine
  # harness mistakes produce different stderr patterns and stay as SYNTAX_ERROR.
  if [[ "$RESULT" == COMPILE_ERROR* ]]; then
    if grep -qE "(is not loaded and could not be found|cannot expand struct)" "$TMP_ERR" 2>/dev/null; then
      RESULT="OK_NEEDS_MODULE"
    else
      RESULT="SYNTAX_ERROR: ${RESULT#COMPILE_ERROR: }"
    fi
  fi
  rm -f "$TMP_ERR"

  case "$RESULT" in
    OK|OK_NEEDS_MODULE)
      OK=$((OK + 1))
      ;;
    SYNTAX_ERROR*)
      BROKEN=$((BROKEN + 1))
      echo "BROKEN: $TASK_NAME"
      echo "  $RESULT"
      ;;
    ERROR*)
      BROKEN=$((BROKEN + 1))
      echo "BROKEN: $TASK_NAME"
      echo "  $RESULT"
      ;;
    *)
      # Empty or unexpected output
      BROKEN=$((BROKEN + 1))
      echo "UNKNOWN: $TASK_NAME"
      ;;
  esac
done

echo ""
echo "Results: $OK/$TOTAL harnesses OK, $BROKEN broken"
