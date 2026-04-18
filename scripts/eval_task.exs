#!/usr/bin/env elixir
# eval_task.exs — Evaluates a single AI solution against a test harness.

for pattern <- ["_build/dev/lib/*/ebin", "_build/test/lib/*/ebin"],
    path <- Path.wildcard(pattern) do
  Code.prepend_path(path)
end

defmodule EvalTask.FailureCollector do
  @moduledoc false
  use GenServer

  @ets_table :eval_task_failures

  def start_link(_opts \\ []) do
    if :ets.whereis(@ets_table) != :undefined do
      :ets.delete(@ets_table)
    end

    :ets.new(@ets_table, [:named_table, :public, :ordered_set])
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get_failures do
    @ets_table
    |> :ets.tab2list()
    |> Enum.map(fn {_key, failure} -> failure end)
  end

  @impl true
  def init(_), do: {:ok, 0}

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{state: nil}}, counter) do
    {:noreply, counter}
  end

  def handle_cast({:test_finished, %ExUnit.Test{} = test}, counter) do
    failure = %{
      test: to_string(test.name),
      module: inspect(test.module),
      message: format_failure(test.state)
    }

    :ets.insert(@ets_table, {counter, failure})
    {:noreply, counter + 1}
  end

  def handle_cast(_msg, counter), do: {:noreply, counter}

  @impl true
  def handle_call(:get_failures, _from, counter) do
    {:reply, get_failures(), counter}
  end

  defp format_failure({:failed, failures}) when is_list(failures) do
    failures
    |> Enum.map_join("\n", fn
      {_kind, %ExUnit.AssertionError{} = e, _stacktrace} ->
        Exception.message(e)

      {_kind, exception, _stacktrace} when is_exception(exception) ->
        Exception.message(exception)

      {kind, reason, _stacktrace} ->
        "#{inspect(kind)}: #{inspect(reason, limit: 300)}"

      other ->
        inspect(other, limit: 300)
    end)
  end

  defp format_failure({:error, {kind, reason, _stack}, _}) do
    "#{inspect(kind)}: #{inspect(reason, limit: 300)}"
  end

  defp format_failure(other), do: inspect(other, limit: 300)
end

defmodule EvalTask do
  @moduledoc false

  # ---------------- MAIN ----------------

  def main(args) do
    :logger.remove_handler(:default)

    {solution_file, harness_file, support_dir} = parse_args(args)

    cond do
      not File.regular?(solution_file) ->
        throw("Solution file does not exist or is not a file")

      not File.regular?(harness_file) ->
        throw("Harness file does not exist or is not a file")

      not is_nil(support_dir) and not File.dir?(support_dir) ->
        throw("Support directory does not exist or is not a directory")

      true ->
        :ok
    end

    result = %{
      solution_file: solution_file,
      test_harness: harness_file,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    compile_support(support_dir)

    source = File.read!(solution_file)

    compile_result = compile_solution(solution_file)
    result = Map.merge(result, compile_result)

    analysis = analyze_source(source)
    result = Map.put(result, :analysis, analysis)

    test_result =
      if compile_result.compiled do
        run_tests(harness_file)
      else
        %{
          tests_ran: false,
          tests_passed: 0,
          tests_failed: 0,
          tests_errors: 0,
          tests_excluded: 0,
          tests_total: 0,
          test_failures: []
        }
      end

    result = Map.merge(result, test_result)

    score = compute_score(result)
    result = Map.put(result, :score, score)

    IO.puts(:json.encode(result))
  end

  # ---------------- ARG PARSING ----------------

  # eval_task.exs 1
  defp parse_args([task]) do
    case Integer.parse(task) do
      {_, ""} ->
        resolve_task_args(task, "001", "solution.ex")

      _ ->
        usage()
    end
  end

  # eval_task.exs 1 2
  defp parse_args([task, variation]) do
    case {Integer.parse(task), Integer.parse(variation)} do
      {{_, ""}, {_, ""}} ->
        resolve_task_args(task, variation, "solution.ex")

      _ ->
        {task, variation, nil}
    end
  end

  # eval_task.exs 1 2 solution.ex
  defp parse_args([task, variation, solution]) do
    case {Integer.parse(task), Integer.parse(variation)} do
      {{_, ""}, {_, ""}} ->
        resolve_task_args(task, variation, solution)

      _ ->
        {task, variation, solution}
    end
  end

  # eval_task.exs solution.ex harness.exs [support]
  defp parse_args([solution, harness, support]) do
    {solution, harness, support}
  end

  defp parse_args([solution, harness]) do
    {solution, harness, nil}
  end

  defp parse_args(_), do: usage()

  defp usage do
    IO.puts(:stderr, "Usage:")
    IO.puts(:stderr, "  elixir eval_task.exs <task>")
    IO.puts(:stderr, "  elixir eval_task.exs <task> <variation>")
    IO.puts(:stderr, "  elixir eval_task.exs <task> <variation> <solution_file>")
    IO.puts(:stderr, "  elixir eval_task.exs <solution> <harness> [support_dir]")
    System.halt(1)
  end

  # ---------------- TASK RESOLUTION ----------------

  defp resolve_task_args(task_str, variation_str, solution_filename) do
    {task, ""} = Integer.parse(task_str)
    {variation, ""} = Integer.parse(variation_str)

    a = String.pad_leading(to_string(task), 3, "0")
    b = String.pad_leading(to_string(variation), 3, "0")
    d = "01"

    pattern =
      "tasks"
      |> Path.join("#{a}_#{b}_*_#{d}")

    dirs =
      pattern
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)

    case dirs do
      [dir] ->
        {
          Path.join(dir, solution_filename),
          Path.join(dir, "test_harness.exs"),
          nil
        }

      [] ->
        throw("No task directory found matching #{pattern}")

      many ->
        throw("Multiple matches found: #{inspect(many)}")
    end
  end

  # ---------------- REST (unchanged) ----------------

  defp compile_support(dir) do
    if dir && File.dir?(dir) do
      dir
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.each(fn file ->
        try do
          Code.compile_file(file)
        rescue
          e -> IO.puts(:stderr, "Warning: could not compile support #{file}: #{inspect(e)}")
        end
      end)
    end
  end

  defp format_diagnostic(d) do
    position =
      case d.position do
        {line, col} -> "#{line}:#{col}"
        line when is_integer(line) -> "#{line}"
        _ -> "?"
      end

    %{type: "diagnostic", severity: d.severity, message: "#{d.file}:#{position}: #{d.message}"}
  end

  defp compile_solution(path) do
    {result, diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          Code.compile_file(path)
          :ok
        rescue
          e -> {:error, e}
        catch
          kind, reason -> {:error, {kind, reason}}
        end
      end)

    warnings = Enum.filter(diagnostics, &(&1.severity == :warning))
    errors = Enum.filter(diagnostics, &(&1.severity == :error))

    case result do
      :ok ->
        %{
          compiled: true,
          compile_warnings: length(warnings),
          compile_warning_messages: Enum.map(warnings, &format_diagnostic/1),
          compile_errors: []
        }

      {:error, %{__struct__: type} = e} ->
        %{
          compiled: false,
          compile_warnings: length(warnings),
          compile_warning_messages: Enum.map(warnings, &format_diagnostic/1),
          compile_errors:
            [%{type: inspect(type), message: Exception.message(e)}] ++
              Enum.map(errors, &format_diagnostic/1)
        }

      {:error, {kind, reason}} ->
        %{
          compiled: false,
          compile_warnings: length(warnings),
          compile_warning_messages: Enum.map(warnings, &format_diagnostic/1),
          compile_errors:
            [%{type: "#{inspect(kind)}", message: inspect(reason)}] ++
              Enum.map(errors, &format_diagnostic/1)
        }
    end
  end

  defp run_tests(harness_file) do
    :logger.update_handler_config(:default, :config, %{type: :standard_error})

    {:ok, _} = EvalTask.FailureCollector.start_link()
    Application.ensure_all_started(:stream_data)
    ExUnit.start(autorun: false, formatters: [EvalTask.FailureCollector])

    compile_result =
      try do
        Code.compile_file(harness_file)
        :ok
      rescue
        e -> {:error, Exception.message(e)}
      end

    case compile_result do
      {:error, message} ->
        return_test_error("Test harness compilation failed: #{message}")

      :ok ->
        %{failures: failures, total: total, excluded: excluded} = ExUnit.run()

        test_failures = EvalTask.FailureCollector.get_failures()

        %{
          tests_ran: true,
          tests_passed: max(total - failures - excluded, 0),
          tests_failed: failures,
          tests_errors: 0,
          tests_excluded: excluded,
          tests_total: total,
          test_failures: test_failures
        }
    end
  rescue
    e ->
      return_test_error("Test execution crashed: #{Exception.message(e)}")
  end

  defp return_test_error(message) do
    %{
      tests_ran: false,
      tests_passed: 0,
      tests_failed: 0,
      tests_errors: 1,
      tests_excluded: 0,
      tests_total: 0,
      test_failures: [%{test: "harness_load", message: message}]
    }
  end

  defp analyze_source(source) do
    lines = String.split(source, "\n")
    line_lengths = Enum.map(lines, &String.length/1)

    %{
      has_moduledoc: String.contains?(source, "@moduledoc"),
      has_typespecs: Regex.match?(~r/@spec\s/, source),
      has_doc_on_public_fns: Regex.match?(~r/@doc\s/, source),
      line_count: length(lines),
      max_line_length: Enum.max(line_lengths, fn -> 0 end),
      lines_over_98: Enum.count(line_lengths, &(&1 > 98)),
      public_fn_count: length(Regex.scan(~r/^\s*def\s+\w+/m, source)),
      defp_count: length(Regex.scan(~r/^\s*defp\s+\w+/m, source)),
      todo_count: length(Regex.scan(~r/#\s*(TODO|FIXME|HACK|XXX)/i, source)),
      pipe_chain_count: length(Regex.scan(~r/\|>/m, source)),
      sql_injection_risk: Regex.match?(~r/".*\#\{.*\}.*FROM|WHERE.*\#\{/m, source),
      credo_issues: []
    }
  end

  defp analysis_checks(a) do
    credo_issue_count = length(a.credo_issues)
    credo_points = if credo_issue_count == 0, do: 2, else: max(0, 2 - credo_issue_count * 0.2)

    [
      {2, 2, a.has_moduledoc, "@moduledoc present"},
      {2, 2, a.has_typespecs, "@spec annotations present"},
      {1, 1, a.has_doc_on_public_fns, "@doc on public functions"},
      {1, 1, a.lines_over_98 == 0, "no lines over 98 chars (found #{a.lines_over_98})"},
      {1, 1, a.todo_count == 0, "no TODO/FIXME/HACK comments (found #{a.todo_count})"},
      {1, 1, !a.sql_injection_risk, "no SQL injection risk"},
      {credo_points, 2, credo_issue_count == 0, "credo clean (#{credo_issue_count} issues)"}
    ]
  end

  defp compute_score(result) do
    compilation_score =
      if result.compiled do
        max(0.0, 1.0 - result.compile_warnings * 0.1)
      else
        0.0
      end

    test_score =
      if result.tests_total > 0,
        do: result.tests_passed / result.tests_total,
        else: 0.0

    a = result.analysis
    checks = analysis_checks(a)

    analysis_points = checks |> Enum.map(fn {pts, _, _, _} -> pts end) |> Enum.sum()
    analysis_score = min(analysis_points / 10, 1.0)

    reasons =
      []
      |> then(fn acc ->
        if result.compiled do
          w = result.compile_warnings
          if w > 0,
            do: ["compilation: #{w} warning(s) → -#{Float.round(w * 0.1, 1)} pts" | acc],
            else: acc
        else
          ["compilation: failed to compile (0.0)" | acc]
        end
      end)
      |> then(fn acc ->
        if result.tests_total > 0 and result.tests_failed > 0 do
          ["tests: #{result.tests_failed}/#{result.tests_total} failed" | acc]
        else
          acc
        end
      end)
      |> then(fn acc ->
        check_reasons =
          checks
          |> Enum.reject(fn {pts, max, _passed, _label} -> pts == max end)
          |> Enum.map(fn {pts, max, _passed, label} ->
            "analysis: #{label} → #{pts}/#{max} pts"
          end)

        check_reasons ++ acc
      end)
      |> Enum.reverse()

    overall =
      if result.compiled,
        do: test_score * 0.7 + analysis_score * 0.2 + compilation_score * 0.1,
        else: 0.0

    %{
      compilation: Float.round(compilation_score, 2),
      tests: Float.round(test_score, 2),
      analysis: Float.round(analysis_score, 2),
      overall: Float.round(overall, 2),
      reasons: if(reasons == [], do: ["perfect score — no deductions"], else: reasons)
    }
  end
end

EvalTask.main(System.argv())
