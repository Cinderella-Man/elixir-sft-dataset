defmodule EvalTask.CLI do
  @moduledoc """
  Entry point for `scripts/eval_task.exs`. Resolves the task, detects its shape
  (`:single`, `:multifile`, `:fim`), runs it, and prints one JSON result line.

  ## Invocation forms

      eval_task.exs <task_dir> [solution_file]        # e.g. tasks/016_001_paginated_list_endpoint_01  or  tasks/001_001_rate_limiter_02
      eval_task.exs <task> <variation>                # tasks/<a>_<b>_*_01
      eval_task.exs <task> <variation> <subtask>      # tasks/<a>_<b>_*_<subtask>  (FIM when subtask ≥ 02)
      eval_task.exs <task> <variation> <solution>     # <solution> is a filename inside the resolved dir
      eval_task.exs <solution_path> <harness_path> [support]   # legacy explicit single-file
  """

  alias EvalTask.{Bundle, Runner}

  @doc false
  def main(args) do
    :logger.remove_handler(:default)

    case resolve(args) do
      {:legacy, solution, harness, support} ->
        compile_support(support)

        emit(Runner.run_single_explicit(solution, harness), %{
          solution_file: solution,
          test_harness: harness
        })

      {:ok, task_dir, solution_file} ->
        cond do
          not File.dir?(task_dir) ->
            fail("Task directory not found: #{task_dir}")

          not File.regular?(solution_file) ->
            fail("Solution file not found: #{solution_file}")

          true ->
            shape = detect(task_dir, solution_file)

            result =
              case shape do
                :single -> Runner.run_single(task_dir, solution_file)
                :multifile -> Runner.run_multifile(task_dir, solution_file)
                :fim -> Runner.run_fim(task_dir, solution_file)
                :write_test -> Runner.run_write_test(task_dir, solution_file)
                :test_fim -> Runner.run_test_fim(task_dir, solution_file)
                :bugfix -> Runner.run_bugfix(task_dir, solution_file)
                :adapt -> Runner.run_adapt(task_dir, solution_file)
                :dedoc -> Runner.run_dedoc(task_dir, solution_file)
              end

            emit(result, %{
              task: Path.basename(task_dir),
              shape: shape,
              solution_file: solution_file
            })
        end

      :usage ->
        usage()
    end
  end

  @doc "Detect a task's shape from its directory + chosen solution file."
  @spec detect(String.t(), String.t()) ::
          :single | :multifile | :fim | :write_test | :test_fim | :bugfix | :adapt | :dedoc
  def detect(task_dir, solution_file) do
    base = Path.basename(task_dir)

    cond do
      # New derived kinds are keyed by directory prefix (checked before the harness-less
      # `:fim` default, which a tfim_ dir would otherwise fall into).
      String.starts_with?(base, "wt_") -> :write_test
      String.starts_with?(base, "tfim_") -> :test_fim
      String.starts_with?(base, "bugfix_") -> :bugfix
      String.starts_with?(base, "adapt_") -> :adapt
      String.starts_with?(base, "dedoc_") -> :dedoc
      not File.regular?(Path.join(task_dir, "test_harness.exs")) -> :fim
      Bundle.bundle?(File.read!(solution_file)) -> :multifile
      true -> :single
    end
  end

  # ---------------- resolution ----------------

  defp resolve([arg | rest] = args) do
    cond do
      File.dir?(arg) ->
        solution = solution_from(arg, rest)
        {:ok, arg, solution}

      match?({_, ""}, Integer.parse(arg)) ->
        resolve_numeric(args)

      length(args) >= 2 and File.regular?(arg) ->
        [solution, harness | maybe_support] = args
        {:legacy, solution, harness, List.first(maybe_support)}

      true ->
        :usage
    end
  end

  defp resolve([]), do: :usage

  defp solution_from(dir, []), do: Path.join(dir, "solution.ex")

  defp solution_from(dir, [sol | _]),
    do: if(File.regular?(sol), do: sol, else: Path.join(dir, sol))

  # numeric: [task], [task, variation], [task, variation, subtask|solution]
  defp resolve_numeric([task]), do: resolve_dir(task, "1", "01", nil)

  defp resolve_numeric([task, variation]), do: resolve_dir(task, variation, "01", nil)

  defp resolve_numeric([task, variation, third]) do
    case Integer.parse(third) do
      {n, ""} -> resolve_dir(task, variation, String.pad_leading(to_string(n), 2, "0"), nil)
      _ -> resolve_dir(task, variation, "01", third)
    end
  end

  defp resolve_numeric(_), do: :usage

  defp resolve_dir(task, variation, subtask, solution_name) do
    a = String.pad_leading(task, 3, "0")
    b = String.pad_leading(to_string(elem(Integer.parse(variation), 0)), 3, "0")

    case Path.wildcard("tasks/#{a}_#{b}_*_#{subtask}") |> Enum.filter(&File.dir?/1) do
      [dir] -> {:ok, dir, solution_from(dir, if(solution_name, do: [solution_name], else: []))}
      [] -> fail("No task directory matching tasks/#{a}_#{b}_*_#{subtask}")
      many -> fail("Multiple matches: #{inspect(many)}")
    end
  end

  # ---------------- output ----------------

  defp emit(result, base) do
    result
    |> Map.merge(base)
    |> Map.put_new(:timestamp, DateTime.utc_now() |> DateTime.to_iso8601())
    |> :json.encode()
    |> IO.puts()
  rescue
    # The caller (a killed generation loop) can take stdout down mid-eval; the
    # ErlangError death rattle then spams the appended log and reads like a
    # crash (Kamil hit it twice on 2026-07-12). Nobody is reading the result —
    # exit quietly instead.
    _ -> System.halt(0)
  end

  defp compile_support(nil), do: :ok

  defp compile_support(dir) do
    if File.dir?(dir) do
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

  defp fail(msg) do
    IO.puts(:stderr, msg)
    System.halt(1)
  end

  defp usage do
    IO.puts(:stderr, """
    Usage:
      eval_task.exs <task_dir> [solution_file]
      eval_task.exs <task> <variation> [<subtask>|<solution_file>]
      eval_task.exs <solution_path> <harness_path> [support_dir]
    """)

    System.halt(1)
  end
end
