defmodule GenTask.Base do
  @moduledoc """
  The base generator (see `docs/04-task-generation-loop.md` §8).

  For one todo idea it runs two blind `claude -p` calls — **Step A** turns the idea
  into `prompt.md` + `test_harness.exs`, **Step B** solves that prompt (seeing the
  prompt *only*, never the tests) into `solution.ex` — then drives the shared cycle
  (`GenTask.Cycle`) and, if accepted, promotes the triplet to
  `tasks/NNN_001_slug_01/` behind the safety guard.

  `run/2` returns a single outcome map (see `GenTask.Cycle.outcome/1`); when accepted
  its `:seed` is a task reference the caller uses to chain variations and FIM.
  """

  require Logger

  alias GenTask.{Catalog, Config, Cycle, CycleLog, Reply, Prompts}

  @type seed :: %{
          num: pos_integer(),
          name: String.t(),
          slug: String.t(),
          b: pos_integer(),
          task_id: String.t(),
          files: %{String.t() => String.t()}
        }

  @doc "Generate, cycle, and (if accepted) promote the base task for `idea`."
  @spec run(Catalog.Idea.t(), Config.t()) :: map()
  def run(%Catalog.Idea{} = idea, %Config{} = cfg) do
    handle = CycleLog.open(cfg, idea.task_id)
    Logger.info("BASE #{idea.task_id}: #{idea.name}")

    outcome =
      try do
        generate(idea, cfg)
      rescue
        e ->
          Logger.error(
            "base #{idea.task_id} crashed: " <> Exception.format(:error, e, __STACKTRACE__)
          )

          Cycle.outcome(
            id: idea.task_id,
            kind: :base,
            num: idea.num,
            name: idea.name,
            status: :error,
            reason: Exception.message(e)
          )
      end

    CycleLog.close(handle, close_of(outcome.status))
    outcome
  end

  defp generate(idea, cfg) do
    {sys_a, user_a} = Prompts.base_task(%{num: idea.num, name: idea.name, desc: idea.desc})

    with {:ok, task_files} <-
           gen(cfg, idea.task_id, "base_task", sys_a, user_a, &Reply.validate_task/1),
         {sys_b, user_b} = Prompts.base_solve(task_files["prompt.md"]),
         {:ok, answer} <-
           gen(cfg, idea.task_id, "base_solve", sys_b, user_b, &Reply.validate_answer/1) do
      files = %{
        "prompt.md" => task_files["prompt.md"],
        "test_harness.exs" => task_files["test_harness.exs"],
        "solution.ex" => answer["solution.ex"]
      }

      ctx = %{
        dir: Path.join(cfg.staging_dir, idea.task_id),
        mutant_dir: Path.join(cfg.staging_dir, idea.task_id <> "_mut"),
        id: idea.task_id
      }

      result = Cycle.run(files, ctx, cfg)
      stats = Cycle.grade_stats(result.grade)

      if result.status == :accepted do
        _ = Cycle.promote(cfg, idea.task_id, result.files)
        base_outcome(idea, :accepted, result, stats, seed(idea, result.files))
      else
        base_outcome(
          idea,
          :rejected,
          result,
          stats,
          nil,
          result.reason || Cycle.reason_for(result.grade)
        )
      end
    else
      {:error, reason} ->
        Logger.error("base #{idea.task_id}: generation failed: #{inspect(reason)}")

        Cycle.outcome(
          id: idea.task_id,
          kind: :base,
          num: idea.num,
          name: idea.name,
          status: :error,
          reason: inspect(reason)
        )
    end
  end

  defp base_outcome(idea, status, result, stats, seed, reason \\ nil) do
    Cycle.outcome(
      id: idea.task_id,
      kind: :base,
      num: idea.num,
      name: idea.name,
      status: status,
      attempts: result.attempts,
      compiled: stats.compiled,
      tests_passed: stats.tests_passed,
      tests_failed: stats.tests_failed,
      tests_total: stats.tests_total,
      mutant_failed: result.mutant_failed,
      mutation: result.mutation,
      reason: reason,
      seed: seed
    )
  end

  defp seed(idea, files) do
    %{num: idea.num, name: idea.name, slug: idea.slug, b: 1, task_id: idea.task_id, files: files}
  end

  # Generate + parse + contract-validate, with one reminder retry on a contract miss
  # (shared shape — see Cycle.generate/7).
  defp gen(cfg, id, step, system, user, validator) do
    Cycle.generate(cfg, id, step, system, user, validator)
  end

  defp close_of(:accepted), do: :ok
  defp close_of(_), do: :error
end
