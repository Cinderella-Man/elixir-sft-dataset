#!/usr/bin/env elixir
# generate.exs — deterministic, non-agentic task-generation loop.
#
# Walks tasks/tasks.md and, for each todo base idea, drives Claude Opus (via the
# `claude` CLI subprocess) through a fixed procedure that authors a single-file task,
# its variations, and FIM subtasks — grading each with scripts/eval_task.exs, repairing
# on failure, and gating on green + house-style (moduledoc/spec/doc, no TODO, zero
# warnings) + a per-function mutation check. Also backfills/top-ups derivatives for
# existing accepted _01s. See docs/04-task-generation-loop.md (design) and
# docs/05-generation-loop-audit.md (audit + rationale for the gates).
#
# Runs under `mix run` so lib/gen_task/** is compiled and available.
#
#   mix run scripts/generate.exs            # whole catalog
#   mix run scripts/generate.exs 80         # a single base idea
#   GEN_LIMIT=5 mix run scripts/generate.exs
#   GEN_DRY_RUN=1 mix run scripts/generate.exs 80

# The generation model is HARDCODED to Opus. This overrides any GEN_MODEL value
# leaking in from the environment, so an interactive session's saved default (e.g.
# Fable) can never silently become the generation model. The transport already
# passes `--model` explicitly with `--setting-sources ''`, so the CLI's saved
# default cannot apply either — this line closes the remaining env-var path.
System.put_env("GEN_MODEL", "opus")

GenTask.CLI.main(System.argv())
