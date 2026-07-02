defmodule GenTask.CLI do
  @moduledoc """
  Entry point for `scripts/generate.exs` (see `docs/04-task-generation-loop.md` §4, §16).

  `main/1` resolves the run config, captures an in-memory catalog snapshot, and drives
  the two sequential work-lists:

    1. **new bases** — each todo idea is generated, and only if accepted are its
       variations and FIM subtasks chained from it;
    2. **backfill** — existing accepted `_01`s that lack variations and/or FIM get just
       the missing derivatives.

  Each item is wrapped in a rescue so one failure never kills the loop. Terminal
  progress is printed with `IO.puts` (`run_all.exs` style); full prompts/responses go
  only to the per-cycle log files. `plan/1` (pure enumeration) is exposed so the
  work-list can be inspected without any `claude` call.
  """

  require Logger

  alias GenTask.{Base, Catalog, Config, CycleLog, Fim, Mutation, Variations}

  @doc "Run the generation loop from `argv` + the process environment."
  @spec main([String.t()]) :: :ok
  def main(argv) do
    cfg = Config.new(argv)
    CycleLog.startup(cfg)

    plan = plan(cfg)
    names = Map.new(plan.ideas, &{&1.num, &1.name})

    print_header(cfg, plan)

    run_bases(plan.bases, cfg)
    run_backfill(plan.backfill, names, cfg)

    IO.puts("\nDone.")
    :ok
  end

  @doc """
  Compute the run's work-lists without performing any generation:
  `%{ideas: [...], bases: [...], backfill: [...]}`.
  """
  @spec plan(Config.t()) :: %{
          ideas: [Catalog.Idea.t()],
          bases: [Catalog.Idea.t()],
          backfill: [Catalog.Seed.t()]
        }
  def plan(%Config{} = cfg) do
    ideas = Catalog.ideas(cfg)
    bases = if cfg.only == :backfill, do: [], else: Catalog.todo_bases(ideas, cfg)

    backfill =
      if cfg.skip_backfill or cfg.only == :bases, do: [], else: Catalog.backfill_seeds(cfg)

    %{ideas: ideas, bases: bases, backfill: backfill}
  end

  # ------------------------------------------------------------------
  # Work-list 1: new bases (chained)
  # ------------------------------------------------------------------

  defp run_bases([], _cfg), do: :ok

  defp run_bases(bases, cfg) do
    n = length(bases)

    bases
    |> Enum.with_index(1)
    |> Enum.each(fn {idea, i} -> run_base_item(idea, "[#{pad(i, n)}/#{n}]", cfg) end)
  end

  defp run_base_item(idea, tag, cfg) do
    cond do
      errored?(cfg, idea.task_id) and not cfg.retry_failed ->
        IO.puts(
          "#{tag} #{idea.task_id} (base) ... SKIPPED (prior failure; GEN_RETRY_FAILED=1 to retry)"
        )

      true ->
        try do
          {ms, out} = timed(fn -> Base.run(idea, cfg) end)
          record_and_print(cfg, tag, out, ms)

          if out.status == :accepted do
            variation_seeds = run_variations(cfg, out.seed)
            run_fim(cfg, [out.seed | variation_seeds])
          end
        rescue
          e ->
            IO.puts("#{tag} #{idea.task_id} (base) ... ERROR (#{Exception.message(e)})")
            Logger.error("base item crashed: " <> Exception.format(:error, e, __STACKTRACE__))
        end
    end
  end

  # ------------------------------------------------------------------
  # Work-list 2: backfill
  # ------------------------------------------------------------------

  defp run_backfill([], _names, _cfg), do: :ok

  defp run_backfill(seeds, names, cfg) do
    IO.puts("\nBackfill: #{length(seeds)} seed(s) needing derivatives.")

    seeds
    |> Enum.with_index(1)
    |> Enum.each(fn {seed, i} ->
      run_backfill_item(seed, names, "[#{pad(i, length(seeds))}/#{length(seeds)}]", cfg)
    end)
  end

  defp run_backfill_item(seed, names, tag, cfg) do
    try do
      files = read_triplet(seed.dir)
      name = Map.get(names, seed.num, humanize(slug_of(seed.task_id)))
      IO.puts("#{tag} #{seed.task_id} (backfill) ...")

      if files, do: warn_if_vacuous_seed(cfg, seed, files)

      variation_seeds =
        if seed.needs_variations? and files do
          base_ref = %{
            num: seed.num,
            name: name,
            slug: slug_of(seed.task_id),
            b: 1,
            task_id: seed.task_id,
            files: files
          }

          run_variations(cfg, base_ref)
        else
          []
        end

      own_fim =
        if seed.needs_fim? and files do
          [
            %{
              num: seed.num,
              slug: slug_of(seed.task_id),
              b: seed.b,
              task_id: seed.task_id,
              files: files
            }
          ]
        else
          []
        end

      run_fim(cfg, own_fim ++ variation_seeds)
    rescue
      e ->
        IO.puts("#{tag} #{seed.task_id} (backfill) ... ERROR (#{Exception.message(e)})")
        Logger.error("backfill item crashed: " <> Exception.format(:error, e, __STACKTRACE__))
    end
  end

  # A backfill seed is taken as-is (§4): its own harness is never a blocker, but if it
  # can't kill a raise-mutant we log a warning — a vacuous seed harness is a smell even
  # though we still derive from it.
  defp warn_if_vacuous_seed(cfg, seed, files) do
    mutant_dir = Path.join(cfg.staging_dir, seed.task_id <> "_seedmut")

    case Mutation.gate_base(mutant_dir, files, cfg) do
      :survived ->
        Logger.warning(
          "backfill seed #{seed.task_id}: its own harness does NOT kill a mutant " <>
            "(vacuous) — deriving anyway"
        )

      :killed ->
        :ok
    end
  rescue
    e ->
      Logger.warning(
        "backfill seed #{seed.task_id}: mutation self-check failed: #{Exception.message(e)}"
      )
  end

  # ------------------------------------------------------------------
  # Derivative drivers
  # ------------------------------------------------------------------

  defp run_variations(%Config{skip_variations: true}, _seed), do: []

  defp run_variations(cfg, base_seed) do
    outs = Variations.run(base_seed, cfg)
    Enum.each(outs, &record_and_print(cfg, "     ", &1, nil))
    outs |> Enum.filter(&(&1.status == :accepted)) |> Enum.map(& &1.seed)
  end

  defp run_fim(%Config{skip_fim: true}, _seeds), do: :ok

  defp run_fim(cfg, seeds) do
    Enum.each(seeds, fn seed ->
      seed
      |> Fim.run(cfg)
      |> Enum.each(&record_and_print(cfg, "     ", &1, nil))
    end)
  end

  # ------------------------------------------------------------------
  # Reporting
  # ------------------------------------------------------------------

  defp record_and_print(cfg, tag, out, ms) do
    IO.puts("#{tag} #{line(out)}")

    CycleLog.record_run(cfg, %{
      id: out.id,
      kind: out.kind,
      num: out.num,
      name: out.name,
      outcome: out.status,
      attempts: out.attempts,
      compiled: out.compiled,
      tests_passed: out.tests_passed,
      tests_failed: out.tests_failed,
      tests_total: out.tests_total,
      mutant_failed: out.mutant_failed,
      elapsed_s: ms && Float.round(ms / 1000, 1)
    })
  end

  defp line(out) do
    "#{out.id} (#{out.kind}) ... #{status_text(out)}"
  end

  defp status_text(%{status: :accepted} = o) do
    mutant = if o.mutant_failed, do: "mutant killed", else: "mutant survived?"
    "ACCEPTED (#{o.tests_passed} passed, #{mutant}, #{o.attempts} attempt(s))"
  end

  defp status_text(%{status: :rejected} = o), do: "REJECTED (#{o.reason})"
  defp status_text(%{status: :skipped} = o), do: "SKIPPED (#{o.reason})"
  defp status_text(%{status: :error} = o), do: "ERROR (#{o.reason})"

  defp print_header(cfg, plan) do
    mode = if cfg.dry_run, do: " [DRY-RUN — no promotion / tasks.md edits]", else: ""

    IO.puts("""
    =============================================
      GenTask — task generation loop#{mode}
      model=#{cfg.model}  max_retries=#{cfg.max_retries}  fim_max=#{cfg.fim_max_per_task}
      new bases: #{length(plan.bases)}   backfill seeds: #{length(plan.backfill)}
    =============================================
    """)
  end

  # ------------------------------------------------------------------
  # helpers
  # ------------------------------------------------------------------

  defp errored?(%Config{logs_dir: logs_dir}, id),
    do: File.exists?(Path.join([logs_dir, "errors", "#{id}.log"]))

  defp read_triplet(dir) do
    files =
      for f <- ["prompt.md", "test_harness.exs", "solution.ex"],
          path = Path.join(dir, f),
          File.regular?(path),
          into: %{},
          do: {f, File.read!(path)}

    if map_size(files) == 3, do: files, else: nil
  end

  defp slug_of(task_id) do
    task_id
    |> String.split("_")
    |> Enum.drop(2)
    |> Enum.drop(-1)
    |> Enum.join("_")
  end

  defp humanize(slug), do: slug |> String.replace("_", " ")

  defp timed(fun) do
    t0 = System.monotonic_time(:millisecond)
    result = fun.()
    {System.monotonic_time(:millisecond) - t0, result}
  end

  defp pad(i, n), do: String.pad_leading(to_string(i), String.length(to_string(n)))
end
