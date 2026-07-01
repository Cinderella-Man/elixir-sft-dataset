#!/usr/bin/env elixir
# eval_task.exs — Evaluate one AI solution against its test harness.
#
# The evaluator logic lives in lib/eval_task/ (compiled with the project); this
# script is a thin entry point so it works under both `mix run` and bare `elixir`
# (as scripts/run_all.exs invokes it). Run `mix compile` after changing lib/.
#
# Handles three task shapes: single-file, multi-file (<file> bundles), and
# fill-in-the-middle (FIM). See EvalTask.CLI for invocation forms.

for pattern <- ["_build/dev/lib/*/ebin", "_build/test/lib/*/ebin"],
    path <- Path.wildcard(pattern) do
  Code.prepend_path(path)
end

EvalTask.CLI.main(System.argv())
