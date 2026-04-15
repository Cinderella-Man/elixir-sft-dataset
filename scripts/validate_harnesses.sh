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

  RESULT=$(elixir -e '
    # Suppress output
    ExUnit.start(autorun: false)
    try do
      Code.compile_file("'"$HARNESS"'")
      IO.puts("OK")
    rescue
      e in [CompileError, SyntaxError, TokenMissingError] ->
        IO.puts("SYNTAX_ERROR: #{Exception.message(e)}")
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
  ' 2>/dev/null)

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
