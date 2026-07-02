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

  @doc """
  Select FIM candidates for `seed` and generate/promote a subtask for each.

  Targets already covered by an existing `_0d` subtask, or permanently rejected on a
  prior run (recorded in `logs/fim_rejected.jsonl` — the parent harness does not
  exercise them), are excluded from selection so a top-up run picks NEW targets and an
  unfixable candidate is never re-attempted.
  """
  @spec run(seed(), Config.t()) :: [map()]
  def run(seed, %Config{} = cfg) do
    # Top-up cap: only generate up to `fim_max_per_task` FIM subtasks per `_01` in
    # TOTAL, so a partially-derived `_01` (backfill) requests only the missing count
    # rather than another full `fim_max` batch.
    limit = max(0, cfg.fim_max_per_task - existing_fim_count(seed, cfg))
    excluded = excluded_targets(seed, cfg)

    case limit > 0 && select_candidates(seed, cfg, excluded, limit) do
      false ->
        []

      {[], nil} ->
        []

      {[], out} ->
        [out]

      {targets, _} ->
        start_d = next_subtask_index(seed, cfg)

        {outs, _next} =
          targets
          |> Enum.with_index()
          |> Enum.reduce({[], start_d}, fn {target, i}, {acc, d} ->
            {out, promoted?} = build_candidate(seed, target, d, i, cfg)
            {[out | acc], if(promoted?, do: d + 1, else: d)}
          end)

        Enum.reverse(outs)
    end
  end

  # Targets we must NOT select: functions already turned into a `_0d` subtask, plus
  # targets permanently rejected on a prior run.
  defp excluded_targets(seed, cfg) do
    rejected = MapSet.new(CycleLog.rejected_fim_targets(cfg, prefix(seed)))
    MapSet.union(covered_targets(seed, cfg), rejected)
  end

  # `name/arity` of the function each existing `_0d` subtask already fills (its
  # solution.ex is just that one function).
  defp covered_targets(seed, cfg) do
    seed
    |> existing_fim_dirs(cfg)
    |> Enum.flat_map(fn d -> fn_targets(Path.join(d, "solution.ex")) end)
    |> MapSet.new()
  end

  defp existing_fim_count(seed, cfg), do: seed |> existing_fim_dirs(cfg) |> length()

  defp existing_fim_dirs(seed, cfg) do
    Path.join(cfg.tasks_dir, "#{prefix(seed)}_*")
    |> Path.wildcard()
    |> Enum.filter(fn d -> File.dir?(d) and fim_subtask_dir?(Path.basename(d)) end)
  end

  defp fim_subtask_dir?(basename) do
    case subtask_index(basename) do
      n when is_integer(n) -> n >= 2
      _ -> false
    end
  end

  # Parse a (single-function) solution.ex into `["name/arity", ...]`.
  defp fn_targets(path) do
    with {:ok, src} <- File.read(path),
         {:ok, ast} <- Code.string_to_quoted(src) do
      {_ast, acc} =
        Macro.prewalk(ast, [], fn
          {op, _m, [head | _]} = node, acc when op in [:def, :defp] ->
            case na(head) do
              {n, a} -> {node, ["#{n}/#{a}" | acc]}
              nil -> {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      acc
    else
      _ -> []
    end
  end

  defp na({:when, _, [inner | _]}), do: na(inner)
  defp na({name, _, args}) when is_atom(name) and is_list(args), do: {name, length(args)}
  defp na({name, _, nil}) when is_atom(name), do: {name, 0}
  defp na(_), do: nil

  # ------------------------------------------------------------------
  # Candidate selection (its own log file)
  # ------------------------------------------------------------------

  defp select_candidates(seed, cfg, excluded, limit) do
    sel_id = "#{prefix(seed)}_fim_select"
    handle = CycleLog.open(cfg, sel_id)
    Logger.info("FIM candidate-select for #{seed.task_id} (up to #{limit})")

    result =
      try do
        {system, user} =
          Prompts.fim_select(
            seed.files["solution.ex"],
            seed.files["prompt.md"],
            limit,
            MapSet.to_list(excluded)
          )

        case Cycle.opus(cfg, seed.task_id, "fim_select", system, user) do
          {:ok, text, _meta} ->
            {:targets, parse_candidates(text, limit, excluded)}

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

  defp parse_candidates(text, max, excluded) do
    text
    |> Reply.parse()
    |> Map.get("candidates.md", "")
    |> String.split("\n")
    |> Enum.map(&clean_candidate/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&String.contains?(&1, "/"))
    |> Enum.reject(&MapSet.member?(excluded, &1))
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

  # `d` is the contiguous promotion slot (advances only on accept, so promoted `_0d`
  # dirs stay gap-free); `i` is the candidate's 0-based ordinal, used to give every
  # attempt a unique log id so distinct rejects don't overwrite each other's log.
  defp build_candidate(seed, target, d, i, cfg) do
    fim_id = "#{prefix(seed)}_#{pad2(d)}"
    log_id = "#{prefix(seed)}_fim#{pad2(i + 1)}"
    handle = CycleLog.open(cfg, log_id)
    Logger.info("FIM #{log_id} → #{fim_id}: target #{target}")

    {outcome, promoted?} =
      try do
        {system, user} =
          Prompts.fim_candidate(seed.files["solution.ex"], seed.files["prompt.md"], target)

        case gen_fim(cfg, log_id, system, user) do
          {:ok, ff} ->
            run_attempts(seed, target, fim_id, log_id, ff, cfg)

          {:error, reason} ->
            {reject(seed, log_id, target, Cycle.grade_stats(:timeout_or_crash), inspect(reason)),
             false}
        end
      rescue
        e ->
          Logger.error("fim #{log_id} crashed: " <> Exception.format(:error, e, __STACKTRACE__))

          {Cycle.outcome(
             id: log_id,
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
  # FIM shape resolves the parent harness, then loop grade → gate → repair. `fim_id`
  # names the staged `_0d` + the promotion target; `log_id` tags the ledger/outcome
  # for a non-promoted candidate.
  defp run_attempts(seed, target, fim_id, log_id, ff0, cfg) do
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
            {:halt, {reject(seed, log_id, target, stats, Cycle.reason_for(grade)), false}}
          else
            case repair_fim(ff, grade, log_id, cfg) do
              {:ok, ff2} ->
                {:cont, ff2}

              :error ->
                {:halt, {reject(seed, log_id, target, stats, "repair call failed"), false}}
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

            {:survived, _why} ->
              Logger.info(
                "fim #{log_id}: parent harness does not cover #{target} — rejecting candidate"
              )

              # Unfixable here (we may not edit the parent harness): record it so it is
              # not re-selected on a later run.
              CycleLog.record_fim_rejected(cfg, prefix(seed), target)

              {:halt,
               {reject(seed, log_id, target, stats, "parent harness does not cover #{target}"),
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
