defmodule GenTask.Bugfix do
  @moduledoc """
  The bug-repair miner (`bugfix_<a>_<b>_<slug>_NN/` dirs) — decision: docs/13.

  For an accepted single-file `_01`, mints up to `@bugfix_max` DEBUGGING tasks
  **deterministically** (no LLM): each takes one first-order semantic mutant of
  the reference (comparison swap, ±1 on a literal, `:ok`↔`:error`, bool flip —
  `GenTask.Mutation.semantic_mutants/2`) that the parent harness PROVABLY kills,
  and ships:

    * `prompt.md`   — the original task spec + the BUGGY module + the real
      failing-test report captured from the harness run,
    * `solution.ex` — the parent's reference module (the verified fix),
    * `manifest.exs` — the parent's copy when it has one (docs/10 §5.13).

  What this teaches that no existing shape does: bug LOCALIZATION and MINIMAL
  repair from a failing test signal — the model reads real ExUnit output, finds
  a one-token behavior bug in an otherwise-correct module, and fixes it.

  Mint gates (all local evals, no LLM):
    1. the mutant compiles and the parent harness fails against it with at
       least one test failure (`killed_by_tests?` — the failure text becomes
       part of the prompt, so it is real, not synthesized);
    2. the reference passes the same staged harness (re-verified, not assumed);
    3. per-family diversity: candidates are drawn round-robin across mutation
       OPERATOR CLASSES (comparison / literal / atom / boolean), never two of
       the same line.

  Unmintable candidates (mutant survives / does not compile) are ledgered in
  `logs/bugfix_rejected.jsonl` keyed by the solution's content sha — the
  registry count subtracts them, so `missing(:bugfix)` stays honest and a
  backfill pass never re-evaluates a known-dead candidate (the docs/12 §5.1.10
  and §5.1.12 rules).

  Fresh-generation parity: registered as a `:derived` work type in
  `GenTask.Work`, so `work_status` counts it and the `generate.exs` backfill
  executor mints it for every NEW seed automatically.
  """

  require Logger

  alias GenTask.{Config, Cycle, CycleLog, Evaluator, Mutation}

  @bugfix_max 3
  @rejected_ledger "bugfix_rejected.jsonl"
  # keep prompts readable: at most this many failing tests quoted in the report
  @report_failures 4

  @type seed :: %{
          optional(:name) => String.t(),
          num: pos_integer(),
          slug: String.t(),
          b: pos_integer(),
          task_id: String.t(),
          files: %{String.t() => String.t()}
        }

  @doc "Mint bugfix subtasks for `seed`, up to the cap, skipping covered/rejected mutants."
  @spec run(seed(), Config.t()) :: [map()]
  def run(seed, %Config{} = cfg) do
    solution = seed.files["solution.ex"]

    if EvalTask.Bundle.bundle?(solution) do
      # v1 scope: single-module parents only (the harness-vs-mutant staging for
      # bundles needs the tier kits; revisit with the docs/13 v2 items).
      []
    else
      slots = @bugfix_max - existing_count(seed, cfg)

      if slots <= 0,
        do: [],
        else: mint_loop(seed, solution, candidates(seed, cfg), slots, cfg)
    end
  end

  @doc """
  The registry's honest missing-unit count (docs/12 §5.1.10): remaining slots,
  capped by the diverse candidate pool minus covered minus ledger-rejected.
  Bundle parents and unreadable dirs count 0.
  """
  @spec missing_units(
          %{:task_id => String.t(), :dir => String.t(), optional(any()) => any()},
          Config.t()
        ) :: non_neg_integer()
  def missing_units(seed, %Config{} = cfg) do
    pseudo = %{task_id: seed.task_id, files: %{}}
    slots = @bugfix_max - existing_count(pseudo, cfg)

    with true <- slots > 0,
         {:ok, solution} <- File.read(Path.join(seed.dir, "solution.ex")),
         false <- EvalTask.Bundle.bundle?(solution) do
      pseudo = %{task_id: seed.task_id, files: %{"solution.ex" => solution}}
      min(slots, length(candidates(pseudo, cfg)))
    else
      _ -> 0
    end
  end

  # Diverse mutant candidates: round-robin across operator classes, one per
  # source line, minus already-covered labels and ledger-rejected labels.
  @doc false
  def candidates(seed, cfg) do
    solution = seed.files["solution.ex"]
    sha = CycleLog.content_sha(solution)
    covered = covered_labels(seed, cfg)
    rejected = rejected_labels(cfg, prefix(seed), sha)

    solution
    |> Mutation.semantic_mutants()
    |> Enum.reject(fn {label, _} ->
      MapSet.member?(covered, label) or MapSet.member?(rejected, label)
    end)
    |> Enum.uniq_by(fn {label, _} -> line_of(label) end)
    |> Enum.group_by(fn {label, _} -> op_class(label) end)
    |> Map.values()
    |> round_robin()
  end

  defp mint_loop(seed, solution, candidates, slots, cfg) do
    start_n = next_index(seed, cfg)

    {outs, _n, _left} =
      Enum.reduce(candidates, {[], start_n, slots}, fn cand, {acc, n, left} ->
        if left <= 0 do
          {acc, n, left}
        else
          {out, promoted?} = build_candidate(seed, solution, cand, n, cfg)

          {[out | acc], if(promoted?, do: n + 1, else: n),
           if(promoted?, do: left - 1, else: left)}
        end
      end)

    Enum.reverse(outs)
  end

  defp build_candidate(seed, solution, {label, mutated}, n, cfg) do
    id = "bugfix_#{prefix(seed)}_#{pad2(n)}"
    handle = CycleLog.open(cfg, id)

    {outcome, promoted?} =
      try do
        gate(seed, solution, label, mutated, id, cfg)
      rescue
        e ->
          Logger.error("bugfix #{id} crashed: " <> Exception.format(:error, e, __STACKTRACE__))
          {outcome(id, seed, label, :error, reason: Exception.message(e)), false}
      end

    CycleLog.close(handle, if(outcome.status == :accepted, do: :ok, else: :error))
    {outcome, promoted?}
  end

  defp gate(seed, solution, label, mutated, id, cfg) do
    # NOT `id <> "_stage"`: the id starts with "bugfix_", and the eval's shape
    # detection routes THAT prefix to run_bugfix — the staging dir must grade as
    # a plain :single/:multifile triplet (found live in the pilot).
    stage = Path.join(cfg.staging_dir, "stage_" <> id)

    files =
      %{
        "prompt.md" => "bugfix staging",
        "solution.ex" => solution,
        "test_harness.exs" => seed.files["test_harness.exs"]
      }
      |> merge_manifest(seed)

    dir = Evaluator.stage!(stage, files)

    mutant_path = Path.join(cfg.staging_dir, id <> "_mutant.ex")
    File.write!(mutant_path, mutated)
    mutant_grade = Evaluator.grade(dir, cfg, mutant_path)
    ref_grade = Evaluator.grade(dir, cfg)

    cond do
      not Evaluator.killed_by_tests?(mutant_grade) ->
        record_rejected(seed, label, cfg)

        {outcome(id, seed, label, :rejected,
           reason:
             "mutant not killed by tests (survives or fails to compile) — not a mintable bug"
         ), false}

      not Evaluator.green?(ref_grade) ->
        # The parent gold not green against its own harness would be corpus rot;
        # do NOT ledger the mutant (it is not the mutant's fault) — surface loudly.
        {outcome(id, seed, label, :error,
           reason: "reference NOT green against its own staged harness — investigate the parent"
         ), false}

      true ->
        {:ok, report} = failure_report(mutant_grade)
        promote(seed, solution, label, mutated, report, id, cfg)

        {outcome(id, seed, label, :accepted,
           reason: nil,
           stats: Cycle.grade_stats(ref_grade),
           mutation: "semantic_killed"
         ), true}
    end
  end

  defp promote(seed, solution, label, mutated, report, id, cfg) do
    dir = Path.join(cfg.tasks_dir, id)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "prompt.md"), prompt_md(seed, mutated, report))
    File.write!(Path.join(dir, "solution.ex"), solution)

    case seed.files["manifest.exs"] do
      nil -> :ok
      m -> File.write!(Path.join(dir, "manifest.exs"), m)
    end

    Logger.info("BUGFIX #{id} minted (#{label})")
  end

  @doc "The bugfix `prompt.md`: task spec + buggy module + the real failing report."
  @spec prompt_md(map(), String.t(), String.t()) :: String.t()
  def prompt_md(seed, mutated, report) do
    """
    # Fix the bug

    The module below was written for the task that follows, but ONE behavior bug
    slipped in. The test suite (not shown) fails with the report at the bottom.
    Find the bug and fix it — change as little as possible; do not restructure
    working code. Reply with the complete corrected module.

    ## The task the module implements

    #{String.trim_trailing(seed.files["prompt.md"])}

    ## The buggy module

    ```elixir
    #{String.trim_trailing(mutated)}
    ```

    ## Failing test report

    ```
    #{String.trim_trailing(report)}
    ```
    """
  end

  # The real ExUnit failure text from the mutant grade — the prompt's bug signal.
  defp failure_report({:ok, json}) do
    failures =
      (json["test_failures"] || [])
      |> Enum.take(@report_failures)
      |> Enum.map_join("\n\n", fn f ->
        "  * #{f["test"]}\n#{indent(String.slice(to_string(f["message"] || ""), 0, 500))}"
      end)

    total = json["tests_failed"] || 0

    {:ok,
     "#{total} of #{json["tests_total"]} test(s) failed:\n\n" <>
       failures <>
       if(total > @report_failures, do: "\n\n  (…#{total - @report_failures} more)", else: "")}
  end

  defp indent(s), do: s |> String.split("\n") |> Enum.map_join("\n", &("      " <> &1))

  # ── label parsing: diversity classes ─────────────────────────────────────────

  @doc false
  def op_class(label) do
    cond do
      String.contains?(label, "return :") or String.contains?(label, ":ok") or
          String.contains?(label, ":error") ->
        :atom

      Regex.match?(~r/(true|false)\s*->/, label) ->
        :boolean

      Regex.match?(~r/[<>=]+\s*->\s*[<>=]+/, label) ->
        :comparison

      true ->
        :literal
    end
  end

  defp line_of(label) do
    case Regex.run(~r/L(\d+)/, label) do
      [_, l] -> l
      _ -> label
    end
  end

  defp round_robin(groups) do
    groups
    |> Enum.map(&Enum.to_list/1)
    |> interleave([])
  end

  defp interleave(groups, acc) do
    case Enum.reject(groups, &(&1 == [])) do
      [] -> Enum.reverse(acc)
      gs -> interleave(Enum.map(gs, &tl/1), Enum.reduce(gs, acc, fn [h | _], a -> [h | a] end))
    end
  end

  # ── bookkeeping (mirror of TestFim's) ────────────────────────────────────────

  defp existing_dirs(seed, cfg) do
    Path.join(cfg.tasks_dir, "bugfix_#{prefix(seed)}_*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
  end

  defp existing_count(seed, cfg), do: seed |> existing_dirs(cfg) |> length()

  # Mutant labels already shipped: recorded in each dir's prompt? No — the label
  # is not reproducible from the dir, so covered = the mutated module bodies.
  # Cheaper and exact: a candidate whose MUTATED SOURCE equals a shipped buggy
  # module is covered (compare by sha of the fenced module in prompt.md).
  defp covered_labels(seed, cfg) do
    shipped =
      seed
      |> existing_dirs(cfg)
      |> Enum.map(fn d ->
        case File.read(Path.join(d, "prompt.md")) do
          {:ok, p} ->
            case Regex.run(~r/## The buggy module\n\n```elixir\n(.*?)\n```/s, p) do
              [_, body] -> CycleLog.content_sha(body)
              _ -> nil
            end

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    solution = seed.files["solution.ex"]

    solution
    |> Mutation.semantic_mutants()
    |> Enum.filter(fn {_label, mutated} ->
      MapSet.member?(shipped, CycleLog.content_sha(String.trim_trailing(mutated)))
    end)
    |> Enum.map(&elem(&1, 0))
    |> MapSet.new()
  end

  defp rejected_labels(cfg, prefix, sha) do
    path = Path.join(cfg.logs_dir, @rejected_ledger)

    case File.read(path) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.reduce(MapSet.new(), fn line, acc ->
          case JSON.decode(line) do
            {:ok, %{"prefix" => ^prefix, "sha" => ^sha, "label" => label}} ->
              MapSet.put(acc, label)

            _ ->
              acc
          end
        end)

      _ ->
        MapSet.new()
    end
  end

  defp record_rejected(seed, label, cfg) do
    File.mkdir_p!(cfg.logs_dir)

    File.write!(
      Path.join(cfg.logs_dir, @rejected_ledger),
      JSON.encode!(%{
        prefix: prefix(seed),
        sha: CycleLog.content_sha(seed.files["solution.ex"]),
        label: label,
        ts: DateTime.utc_now() |> DateTime.to_iso8601()
      }) <> "\n",
      [:append]
    )
  end

  defp next_index(seed, cfg) do
    existing =
      seed
      |> existing_dirs(cfg)
      |> Enum.map(fn d ->
        case d |> Path.basename() |> String.split("_") |> List.last() |> Integer.parse() do
          {n, ""} -> n
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    case existing do
      [] -> 1
      xs -> Enum.max(xs) + 1
    end
  end

  defp merge_manifest(files, seed) do
    case seed.files["manifest.exs"] do
      nil -> files
      m -> Map.put(files, "manifest.exs", m)
    end
  end

  defp outcome(id, seed, label, status, opts) do
    stats =
      Keyword.get(opts, :stats, %{
        compiled: false,
        tests_passed: 0,
        tests_failed: 0,
        tests_total: 0
      })

    Cycle.outcome(
      id: id,
      kind: :bugfix,
      num: seed.num,
      name: label,
      status: status,
      attempts: 1,
      compiled: stats.compiled,
      tests_passed: stats.tests_passed,
      tests_failed: stats.tests_failed,
      tests_total: stats.tests_total,
      # an accept means the semantic mutant provably FAILED the parent harness
      # (that is where the prompt's failure report comes from) — docs/12 §5.1.5
      mutant_failed: Keyword.get(opts, :mutation) == "semantic_killed",
      mutation: Keyword.get(opts, :mutation),
      reason: opts[:reason]
    )
  end

  defp prefix(seed), do: String.replace_suffix(seed.task_id, "_01", "")
  defp pad2(n), do: String.pad_leading(to_string(n), 2, "0")
end
