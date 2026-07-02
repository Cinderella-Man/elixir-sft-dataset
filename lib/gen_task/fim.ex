defmodule GenTask.Fim do
  @moduledoc """
  The fill-in-the-middle (FIM) generator (see `docs/04-task-generation-loop.md` §10).

  Runs for every accepted `_01` (base + accepted variations). One `claude -p` call
  selects up to `cfg.fim_max_per_task` candidate functions; for each, one more call
  returns a `prompt.md` (description + the whole module with that body replaced by
  `# TODO` inside an ```` ```elixir ```` fence) and a `solution.ex` (just that
  function).

  A candidate is accepted only when the `:fim` grade (the parent `_01` harness passes
  the reconstructed module) is green **and** a raise-mutant of the candidate makes the
  parent harness fail — proving the target is actually exercised. A failing skeleton /
  function is repaired; a mutant that survives means the parent harness does not cover
  the target, so the candidate is rejected (we may not edit the parent harness) and the
  next candidate is tried. Accepted candidates promote to `tasks/NNN_00b_slug_0d/`.

  `run/2` returns a list of outcome maps (one per attempted candidate).
  """

  require Logger

  alias GenTask.{Config, Cycle, CycleLog, Evaluator, Mutation, Prompts, Reply}

  @type seed :: %{
          num: pos_integer(),
          slug: String.t(),
          b: pos_integer(),
          task_id: String.t(),
          files: %{String.t() => String.t()}
        }

  @doc "Select FIM candidates for `seed` and generate/promote a subtask for each."
  @spec run(seed(), Config.t()) :: [map()]
  def run(seed, %Config{} = cfg) do
    case select_candidates(seed, cfg) do
      {[], nil} ->
        []

      {[], out} ->
        [out]

      {targets, _} ->
        start_d = next_subtask_index(seed, cfg)

        {outs, _next} =
          Enum.reduce(targets, {[], start_d}, fn target, {acc, d} ->
            {out, promoted?} = build_candidate(seed, target, d, cfg)
            {[out | acc], if(promoted?, do: d + 1, else: d)}
          end)

        Enum.reverse(outs)
    end
  end

  # ------------------------------------------------------------------
  # Candidate selection (its own log file)
  # ------------------------------------------------------------------

  defp select_candidates(seed, cfg) do
    sel_id = "#{prefix(seed)}_fim_select"
    handle = CycleLog.open(cfg, sel_id)
    Logger.info("FIM candidate-select for #{seed.task_id}")

    result =
      try do
        {system, user} =
          Prompts.fim_select(
            seed.files["solution.ex"],
            seed.files["prompt.md"],
            cfg.fim_max_per_task
          )

        case Cycle.opus(cfg, seed.task_id, "fim_select", system, user) do
          {:ok, text, _meta} ->
            {:targets, parse_candidates(text, cfg.fim_max_per_task)}

          {:error, reason} ->
            {:error, select_error(sel_id, seed, inspect(reason))}
        end
      rescue
        e ->
          Logger.error("fim select crashed: " <> Exception.format(:error, e, __STACKTRACE__))
          {:error, select_error(sel_id, seed, Exception.message(e))}
      end

    case result do
      {:targets, targets} ->
        CycleLog.close(handle, :ok)
        {targets, nil}

      {:error, out} ->
        CycleLog.close(handle, :error)
        {[], out}
    end
  end

  defp select_error(sel_id, seed, reason) do
    Cycle.outcome(
      id: sel_id,
      kind: :fim,
      num: seed.num,
      name: "candidate-select",
      status: :error,
      reason: reason
    )
  end

  defp parse_candidates(text, max) do
    text
    |> Reply.parse()
    |> Map.get("candidates.md", "")
    |> String.split("\n")
    |> Enum.map(&clean_candidate/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&String.contains?(&1, "/"))
    |> Enum.take(max)
  end

  defp clean_candidate(line) do
    line
    |> String.trim()
    |> String.replace(~r/^[-*]\s+/, "")
    |> String.trim("`")
    |> String.trim()
  end

  # ------------------------------------------------------------------
  # Per-candidate generation + accept loop (each in its own log file)
  # ------------------------------------------------------------------

  defp build_candidate(seed, target, d, cfg) do
    fim_id = "#{prefix(seed)}_#{pad2(d)}"
    handle = CycleLog.open(cfg, fim_id)
    Logger.info("FIM #{fim_id}: target #{target}")

    {outcome, promoted?} =
      try do
        {system, user} =
          Prompts.fim_candidate(seed.files["solution.ex"], seed.files["prompt.md"], target)

        case gen_fim(cfg, fim_id, system, user) do
          {:ok, ff} ->
            run_attempts(seed, target, fim_id, ff, cfg)

          {:error, reason} ->
            {reject(seed, fim_id, target, Cycle.grade_stats(:timeout_or_crash), inspect(reason)),
             false}
        end
      rescue
        e ->
          Logger.error("fim #{fim_id} crashed: " <> Exception.format(:error, e, __STACKTRACE__))

          {Cycle.outcome(
             id: fim_id,
             kind: :fim,
             num: seed.num,
             name: target,
             status: :error,
             reason: Exception.message(e)
           ), false}
      end

    CycleLog.close(handle, if(outcome.status == :accepted, do: :ok, else: :error))
    {outcome, promoted?}
  end

  # Stage the parent `_01` (its harness) beside the `_0d` candidate so the eval's
  # FIM shape resolves the parent harness, then loop grade → gate → repair.
  defp run_attempts(seed, target, fim_id, ff0, cfg) do
    stage_parent = Path.join(cfg.staging_dir, "fim_#{fim_id}")
    Evaluator.stage!(Path.join(stage_parent, seed.task_id), seed.files)
    fim_dir = Path.join(stage_parent, fim_id)
    mutant_path = Path.join(stage_parent, "mutant.ex")

    Enum.reduce_while(0..cfg.max_retries, ff0, fn attempt, ff ->
      Evaluator.stage!(fim_dir, %{
        "prompt.md" => ff["prompt.md"],
        "solution.ex" => ff["solution.ex"]
      })

      grade = Evaluator.grade(fim_dir, cfg)
      stats = Cycle.grade_stats(grade)

      cond do
        not Evaluator.green?(grade) ->
          if attempt >= cfg.max_retries do
            {:halt, {reject(seed, fim_id, target, stats, Cycle.reason_for(grade)), false}}
          else
            case repair_fim(ff, grade, fim_id, cfg) do
              {:ok, ff2} ->
                {:cont, ff2}

              :error ->
                {:halt, {reject(seed, fim_id, target, stats, "repair call failed"), false}}
            end
          end

        true ->
          case Mutation.gate_fim(fim_dir, ff["solution.ex"], mutant_path, cfg) do
            :killed ->
              _ =
                Cycle.promote(cfg, fim_id, %{
                  "prompt.md" => ff["prompt.md"],
                  "solution.ex" => ff["solution.ex"]
                })

              {:halt, {accept(seed, fim_id, target, stats, attempt + 1), true}}

            :survived ->
              Logger.info(
                "fim #{fim_id}: parent harness does not cover #{target} — rejecting candidate"
              )

              {:halt,
               {reject(seed, fim_id, target, stats, "parent harness does not cover #{target}"),
                false}}
          end
      end
    end)
  end

  defp repair_fim(ff, grade, fim_id, cfg) do
    report = Evaluator.repair_report({:failed, grade})

    {system, user} =
      Prompts.fix(
        %{"prompt.md" => ff["prompt.md"], "solution.ex" => ff["solution.ex"]},
        report,
        :fim
      )

    case Cycle.opus(cfg, fim_id, "fim_fix", system, user) do
      {:ok, text, _meta} ->
        merged = Map.merge(ff, Reply.parse(text))

        case Reply.validate_fim(merged) do
          :ok ->
            {:ok, merged}

          {:error, msg} ->
            Logger.warning("fim #{fim_id}: fix contract violation (attempt consumed): #{msg}")
            {:ok, ff}
        end

      {:error, reason} ->
        Logger.error("fim #{fim_id}: fix call failed: #{inspect(reason)}")
        :error
    end
  end

  # Generate + parse + contract-validate a candidate, one reminder retry on a miss.
  defp gen_fim(cfg, fim_id, system, user, left \\ 2)

  defp gen_fim(_cfg, _fim_id, _system, _user, 0), do: {:error, :contract}

  defp gen_fim(cfg, fim_id, system, user, left) do
    case Cycle.opus(cfg, fim_id, "fim_candidate", system, user) do
      {:ok, text, _meta} ->
        files = Reply.parse(text)

        case Reply.validate_fim(files) do
          :ok ->
            {:ok, files}

          {:error, msg} ->
            Logger.warning("fim #{fim_id}: contract violation: #{msg} — reminding")

            reminder =
              user <> "\n\nReminder: return ONLY the requested <file> blocks and nothing else."

            gen_fim(cfg, fim_id, system, reminder, left - 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ------------------------------------------------------------------
  # helpers
  # ------------------------------------------------------------------

  defp accept(seed, fim_id, target, stats, attempts) do
    Cycle.outcome(
      id: fim_id,
      kind: :fim,
      num: seed.num,
      name: target,
      status: :accepted,
      attempts: attempts,
      compiled: stats.compiled,
      tests_passed: stats.tests_passed,
      tests_failed: stats.tests_failed,
      tests_total: stats.tests_total,
      mutant_failed: true
    )
  end

  defp reject(seed, fim_id, target, stats, reason) do
    Cycle.outcome(
      id: fim_id,
      kind: :fim,
      num: seed.num,
      name: target,
      status: :rejected,
      compiled: stats.compiled,
      tests_passed: stats.tests_passed,
      tests_failed: stats.tests_failed,
      tests_total: stats.tests_total,
      reason: reason
    )
  end

  defp prefix(seed), do: String.replace_suffix(seed.task_id, "_01", "")

  defp pad2(d), do: String.pad_leading(to_string(d), 2, "0")

  defp next_subtask_index(seed, cfg) do
    existing =
      Path.join(cfg.tasks_dir, "#{prefix(seed)}_*")
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)
      |> Enum.map(&subtask_index(Path.basename(&1)))
      |> Enum.filter(&(is_integer(&1) and &1 >= 2))

    case existing do
      [] -> 2
      xs -> Enum.max(xs) + 1
    end
  end

  defp subtask_index(basename) do
    case basename |> String.split("_") |> List.last() |> Integer.parse() do
      {n, ""} -> n
      _ -> nil
    end
  end
end
