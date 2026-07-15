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
#
#   GEN_PROMISE_AUDIT=1 mix run scripts/generate.exs   # + the accept-time promise
#     audit on every root (T1.10, docs/17 §5.5): one auditor call proposes anchored
#     tests; green ones must bite (isolation mutant) and grow the harness, failing
#     ones machine-prove defects and force a repair. DARK by default until piloted.
#
#   mix run scripts/generate.exs 15 --force # DELETE idea 15's whole family first
#     (base + variations + FIM dirs, wt_/tfim_/bugfix_/adapt_/repair_ children, its
#     tasks.md variation entries, its logs/errors + logs/quarantine blockers), then
#     regenerate it from the catalog idea. Refuses unless every target is git-clean,
#     so the old family is always recoverable with `git checkout`. Combine with
#     GEN_DRY_RUN=1 to print the deletion list without deleting. See GenTask.Force.

# The generation model is HARDCODED to Opus. This overrides any GEN_MODEL value
# leaking in from the environment, so an interactive session's saved default (e.g.
# Fable) can never silently become the generation model. The transport already
# passes `--model` explicitly with `--setting-sources ''`, so the CLI's saved
# default cannot apply either — this line closes the remaining env-var path.
System.put_env("GEN_MODEL", "opus")

GenTask.CLI.main(System.argv())
