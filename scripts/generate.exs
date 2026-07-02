#!/usr/bin/env elixir
# generate.exs — deterministic, non-agentic task-generation loop.
#
# Walks tasks/tasks.md and, for each todo base idea, drives Claude Opus (via the
# `claude` CLI subprocess) through a fixed procedure that authors a single-file task,
# its variations, and FIM subtasks — grading each with scripts/eval_task.exs, repairing
# on failure, and gating on a mutation check. Also backfills derivatives for existing
# accepted _01s. See docs/04-task-generation-loop.md.
#
# Runs under `mix run` so lib/gen_task/** is compiled and available.
#
#   mix run scripts/generate.exs            # whole catalog
#   mix run scripts/generate.exs 80         # a single base idea
#   GEN_LIMIT=5 mix run scripts/generate.exs
#   GEN_DRY_RUN=1 mix run scripts/generate.exs 80

GenTask.CLI.main(System.argv())
