#!/usr/bin/env elixir
# eval_task.exs — Evaluate one AI solution against its test harness.
#
# The evaluator logic lives in lib/eval_task/ (compiled with the project); this
# script is a thin entry point so it works under both `mix run` and bare `elixir`
# (as scripts/run_all.exs invokes it). Run `mix compile` after changing lib/.
#
# Handles three task shapes: single-file, multi-file (<file> bundles), and
# fill-in-the-middle (FIM). See EvalTask.CLI for invocation forms.

# test paths first, dev last: prepend_path puts each entry at the FRONT, so the
# dev beams (what `mix compile` refreshes) must shadow possibly-stale test beams.
for pattern <- ["_build/test/lib/*/ebin", "_build/dev/lib/*/ebin"],
    path <- Path.wildcard(pattern) do
  Code.prepend_path(path)
end

EvalTask.CLI.main(System.argv())
