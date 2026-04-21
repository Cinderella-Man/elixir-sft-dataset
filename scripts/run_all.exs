#!/usr/bin/env elixir
# run_all.exs — Evaluate all solutions against their test harnesses.
#
# Usage:
#   elixir scripts/run_all.exs <solution_filename> [--parallel N]
#
# Looks for the named file inside each task directory:
#   tasks/001_rate_limiter/solution.ex
#   tasks/002_circuit_breaker/solution.ex
#   tasks/076_trie/solution.ex
#
# Outputs:
#   results/<task_name>.json          — per-task result
#   results/report_<timestamp>.json   — combined JSON array
#   results/summary_<timestamp>.txt   — human-readable summary
#   stdout — live progress

defmodule RunAll do
  @moduledoc false

  # ── Entry Point ──────────────────────────────────────────────

  def main(args) do
    {solution_filename, parallel} = parse_args(args)
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d_%H%M%S")

    report_dir = "results"
    report_file = Path.join(report_dir, "report_#{timestamp}.json")
    summary_file = Path.join(report_dir, "summary_#{timestamp}.txt")
    File.mkdir_p!(report_dir)

    print_header(solution_filename)

    # ── Discover tasks and check for solution files ──────────

    tasks = discover_tasks(solution_filename)

    total = length(tasks.all)
    matched = length(tasks.found)
    missing = length(tasks.missing)

    # ── Run evaluations ──────────────────────────────────────

    results =
      if parallel > 1 do
        run_parallel(tasks.found, parallel)
      else
        run_sequential(tasks.found)
      end

    # ── Write per-task result files ──────────────────────────

    Enum.each(results, fn {name, json} ->
      File.write!(Path.join(report_dir, "#{name}.json"), json <> "\n")
    end)

    # ── Write combined report ────────────────────────────────

    json_entries = Enum.map_join(results, ",\n", fn {_name, json} -> json end)
    File.write!(report_file, "[\n#{json_entries}\n]\n")

    # ── Compute and print summary ────────────────────────────

    stats = compute_stats(results)

    summary =
      format_summary(
        total: total,
        matched: matched,
        missing: missing,
        missing_names: tasks.missing,
        stats: stats,
        report_file: report_file,
        summary_file: summary_file
      )

    IO.puts(summary)
    File.write!(summary_file, summary)

    IO.puts("Detailed report: #{report_file}")
    IO.puts("Summary:         #{summary_file}")
  end

  # ── Arg Parsing ──────────────────────────────────────────────

  defp parse_args(args) do
    {opts, positional, _} =
      OptionParser.parse(args, strict: [parallel: :integer])

    solution_filename =
      case positional do
        [name | _] -> name
        _ ->
          IO.puts(:stderr, """
          Usage: elixir scripts/run_all.exs <solution_filename> [--parallel N]

          Examples:
            elixir scripts/run_all.exs solution.ex
            elixir scripts/run_all.exs solution.ex --parallel 4

          Looks for tasks/<task_name>/<solution_filename> in each task directory.
          """)

          System.halt(1)
      end

    parallel = Keyword.get(opts, :parallel, 1)
    {solution_filename, parallel}
  end

  # ── Task Discovery ───────────────────────────────────────────

  defp discover_tasks(solution_filename) do
    Path.wildcard("tasks/*/test_harness.exs")
    |> Enum.map(fn harness ->
      task_dir = Path.dirname(harness)
      name = Path.basename(task_dir)
      solution = Path.join(task_dir, solution_filename)
      %{name: name, dir: task_dir, harness: harness, solution: solution}
    end)
    |> Enum.sort_by(& &1.name)
    |> Enum.split_with(fn task -> File.regular?(task.solution) end)
    |> then(fn {found, missing} ->
      %{
        all: found ++ missing,
        found: found,
        missing: Enum.map(missing, & &1.name)
      }
    end)
  end

  # ── Evaluation Execution ─────────────────────────────────────

  defp run_sequential(tasks) do
    tasks
    |> Enum.with_index(1)
    |> Enum.map(fn {task, idx} ->
      IO.write("[#{idx}] #{task.name} ... ")
      {json, status} = eval_task(task)
      IO.puts(status)
      {task.name, json}
    end)
  end

  defp run_parallel(tasks, max_concurrent) do
    tasks
    |> Enum.with_index(1)
    |> Enum.chunk_every(max_concurrent)
    |> Enum.flat_map(fn chunk ->
      chunk
      |> Enum.map(fn {task, idx} ->
        Task.async(fn ->
          {json, status} = eval_task(task)
          {idx, task.name, json, status}
        end)
      end)
      |> Task.await_many(:infinity)
      |> Enum.sort_by(fn {idx, _, _, _} -> idx end)
      |> Enum.map(fn {idx, name, json, status} ->
        IO.puts("[#{idx}] #{name} ... #{status}")
        {name, json}
      end)
    end)
  end

  defp eval_task(task) do
    args = [
      "scripts/eval_task.exs",
      task.solution,
      task.harness,
      "test/support"
    ]

    case System.cmd("elixir", args, stderr_to_stdout: false) do
      {output, 0} ->
        json = String.trim(output)
        {json, format_status(json)}

      {_output, _code} ->
        json = crash_json(task.solution)
        {json, "CRASH"}
    end
  end

  defp format_status(json) do
    cond do
      String.contains?(json, "\"compiled\":false") or
        String.contains?(json, "\"compiled\": false") ->
        "COMPILE_FAIL"

      match_field(json, "tests_failed") == "0" ->
        passed = match_field(json, "tests_passed")
        "PASS (#{passed} tests)"

      true ->
        failed = match_field(json, "tests_failed")
        passed = match_field(json, "tests_passed")
        "FAIL (#{failed} failed, #{passed} passed)"
    end
  end

  defp match_field(json, field) do
    case Regex.run(~r/"#{field}":\s*(\d+)/, json) do
      [_, value] -> value
      _ -> "?"
    end
  end

  defp crash_json(solution) do
    :json.encode(%{
      solution_file: solution,
      compiled: false,
      compile_errors: [%{type: "crash", message: "Evaluator process crashed"}],
      tests_ran: false,
      tests_passed: 0,
      tests_failed: 0,
      tests_total: 0,
      score: %{compilation: 0, tests: 0, analysis: 0, overall: 0}
    })
  end

  # ── Statistics ───────────────────────────────────────────────

  defp compute_stats(results) do
    jsons = Enum.map(results, fn {_name, json} -> json end)

    compiled = Enum.count(jsons, &compiled?/1)
    compile_fail = length(jsons) - compiled
    tests_ran = Enum.count(jsons, &tests_ran?/1)

    full_pass =
      Enum.count(jsons, fn json ->
        tests_ran?(json) and match_field(json, "tests_failed") == "0"
      end)

    scores =
      jsons
      |> Enum.map(fn json ->
        case Regex.run(~r/"overall":\s*([0-9.]+)/, json) do
          [_, s] -> String.to_float(s)
          _ -> 0.0
        end
      end)

    avg_score =
      if scores == [],
        do: 0.0,
        else: Float.round(Enum.sum(scores) / length(scores), 2)

    %{
      compiled: compiled,
      compile_fail: compile_fail,
      tests_ran: tests_ran,
      full_pass: full_pass,
      avg_score: avg_score
    }
  end

  defp compiled?(json) do
    String.contains?(json, "\"compiled\":true") or
      String.contains?(json, "\"compiled\": true")
  end

  defp tests_ran?(json) do
    String.contains?(json, "\"tests_ran\":true") or
      String.contains?(json, "\"tests_ran\": true")
  end

  # ── Summary Formatting ──────────────────────────────────────

  defp format_summary(opts) do
    total = opts[:total]
    matched = opts[:matched]
    missing = opts[:missing]
    missing_names = opts[:missing_names]
    s = opts[:stats]

    compile_rate =
      if matched > 0,
        do: Float.round(s.compiled * 100 / matched, 1),
        else: 0.0

    pass_rate =
      if matched > 0,
        do: Float.round(s.full_pass * 100 / matched, 1),
        else: 0.0

    missing_section =
      if missing > 0 do
        names = Enum.map_join(missing_names, "\n", &"  - #{&1}")
        "\nMissing solutions:\n#{names}\n"
      else
        ""
      end

    """

    =============================================
      BENCHMARK RESULTS — #{Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S UTC")}
    =============================================

    Tasks discovered:   #{total}
    Solutions found:    #{matched}
    Solutions missing:  #{missing}

    COMPILATION:
      Compiled OK:      #{s.compiled} / #{matched}
      Compile failed:   #{s.compile_fail} / #{matched}
      Compile rate:     #{compile_rate}%

    TESTS:
      All tests passed: #{s.full_pass} / #{matched}
      Pass rate:        #{pass_rate}%

    OVERALL:
      Average score:    #{s.avg_score} / 1.00

    Report: #{opts[:report_file]}
    #{missing_section}
    """
  end

  # ── Header ──────────────────────────────────────────────────

  defp print_header(solution_filename) do
    IO.puts("""
    =============================================
      Elixir Benchmark Suite
      #{Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S UTC")}
      Solution file: #{solution_filename}
    =============================================
    """)
  end
end

# ── Run ──────────────────────────────────────────────────────
RunAll.main(System.argv())
