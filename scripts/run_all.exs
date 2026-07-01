#!/usr/bin/env elixir
# run_all.exs — Evaluate all solutions (single-file, multi-file, and FIM) against
# their harnesses via scripts/eval_task.exs, one OS process (BEAM) per task.
#
# Usage:
#   elixir scripts/run_all.exs [solution_filename] [--parallel N]
#
# Discovers every gradable task through EvalTask.Discovery:
#   * single-file  tasks/<name>/  (has test_harness.exs, plain-module solution)
#   * multi-file   tasks/<name>/  (has test_harness.exs, <file> bundle solution)
#   * FIM          tasks/<name>/  (no harness; reconstructs from parent _01)
#
# Outputs results/<task>.json, results/report_<ts>.json, results/summary_<ts>.txt.

for pattern <- ["_build/dev/lib/*/ebin", "_build/test/lib/*/ebin"],
    path <- Path.wildcard(pattern) do
  Code.prepend_path(path)
end

defmodule RunAll do
  @moduledoc false

  def main(args) do
    {solution_filename, parallel} = parse_args(args)
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d_%H%M%S")
    report_dir = "results"
    File.mkdir_p!(report_dir)

    IO.puts("""
    =============================================
      Elixir Benchmark Suite — #{Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S UTC")}
      Solution file: #{solution_filename}
    =============================================
    """)

    tasks = EvalTask.Discovery.all(solution_filename)
    {found, missing} = Enum.split_with(tasks, & &1.found)

    results = run(found, parallel)

    Enum.each(results, fn {name, json} ->
      File.write!(Path.join(report_dir, "#{name}.json"), json <> "\n")
    end)

    report_file = Path.join(report_dir, "report_#{timestamp}.json")
    File.write!(report_file, "[\n#{Enum.map_join(results, ",\n", fn {_n, j} -> j end)}\n]\n")

    summary = summarize(tasks, found, missing, results, report_file)
    IO.puts(summary)
    summary_file = Path.join(report_dir, "summary_#{timestamp}.txt")
    File.write!(summary_file, summary)
    IO.puts("Detailed report: #{report_file}\nSummary:         #{summary_file}")
  end

  defp parse_args(args) do
    {opts, positional, _} = OptionParser.parse(args, strict: [parallel: :integer])
    solution_filename = List.first(positional) || "solution.ex"
    {solution_filename, Keyword.get(opts, :parallel, 1)}
  end

  defp run(tasks, parallel) when parallel > 1 do
    tasks
    |> Enum.with_index(1)
    |> Enum.chunk_every(parallel)
    |> Enum.flat_map(fn chunk ->
      chunk
      |> Enum.map(fn {task, idx} -> Task.async(fn -> {idx, task, eval(task)} end) end)
      |> Task.await_many(:infinity)
      |> Enum.sort_by(fn {idx, _, _} -> idx end)
      |> Enum.map(fn {idx, task, {json, status}} ->
        IO.puts("[#{idx}] #{task.name} (#{task.shape}) ... #{status}")
        {task.name, json}
      end)
    end)
  end

  defp run(tasks, _seq) do
    tasks
    |> Enum.with_index(1)
    |> Enum.map(fn {task, idx} ->
      IO.write("[#{idx}] #{task.name} (#{task.shape}) ... ")
      {json, status} = eval(task)
      IO.puts(status)
      {task.name, json}
    end)
  end

  defp eval(task) do
    case System.cmd("elixir", ["scripts/eval_task.exs", task.dir, task.solution],
           stderr_to_stdout: false
         ) do
      {output, 0} ->
        json = String.trim(output) |> last_json_line()
        {json, status_of(json)}

      {_output, _code} ->
        {crash_json(task), "CRASH"}
    end
  end

  defp last_json_line(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reverse()
    |> Enum.find("{}", &String.starts_with?(&1, "{"))
  end

  defp status_of(json) do
    case Jason.decode(json) do
      {:ok, %{"skipped" => reason}} -> "SKIP (#{reason})"
      {:ok, %{"compiled" => false}} -> "COMPILE_FAIL"
      {:ok, %{"tests_failed" => 0, "tests_passed" => p}} -> "PASS (#{p})"
      {:ok, %{"tests_failed" => f, "tests_passed" => p}} -> "FAIL (#{f} failed, #{p} passed)"
      _ -> "?"
    end
  end

  defp crash_json(task) do
    Jason.encode!(%{
      task: task.name,
      shape: task.shape,
      compiled: false,
      compile_errors: [%{type: "crash", message: "evaluator process crashed"}],
      tests_ran: false,
      tests_passed: 0,
      tests_failed: 0,
      tests_total: 0,
      score: %{overall: 0}
    })
  end

  defp summarize(all, found, missing, results, report_file) do
    decoded = Enum.map(results, fn {_n, j} -> Jason.decode!(j) end)
    by_shape = Enum.frequencies_by(all, & &1.shape)
    skipped = Enum.count(decoded, &Map.has_key?(&1, "skipped"))
    graded = Enum.reject(decoded, &Map.has_key?(&1, "skipped"))
    compiled = Enum.count(graded, &(&1["compiled"] == true))

    full_pass =
      Enum.count(
        graded,
        &(&1["compiled"] == true and &1["tests_failed"] == 0 and (&1["tests_total"] || 0) > 0)
      )

    scores = Enum.map(graded, &get_in(&1, ["score", "overall"])) |> Enum.reject(&is_nil/1)
    avg = if scores == [], do: 0.0, else: Float.round(Enum.sum(scores) / length(scores), 3)

    matched = length(found)
    rate = fn n -> if matched > 0, do: Float.round(n * 100 / matched, 1), else: 0.0 end

    missing_section =
      if missing == [] do
        ""
      else
        "\nMissing solutions:\n" <>
          Enum.map_join(missing, "\n", &"  - #{&1.name} (#{&1.shape})") <> "\n"
      end

    """

    =============================================
      BENCHMARK RESULTS — #{Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S UTC")}
    =============================================

    Tasks discovered:   #{length(all)}   #{inspect(by_shape)}
    Solutions found:    #{matched}
    Solutions missing:  #{length(missing)}
    Skipped (e.g. PG):  #{skipped}

    COMPILATION:  #{compiled} / #{matched} compiled  (#{rate.(compiled)}%)
    TESTS:        #{full_pass} / #{matched} all-pass  (#{rate.(full_pass)}%)
    OVERALL:      average score #{avg} / 1.0  (over #{length(scores)} graded)

    Report: #{report_file}
    #{missing_section}
    """
  end
end

RunAll.main(System.argv())
