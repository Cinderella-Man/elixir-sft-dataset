#!/usr/bin/env elixir
# validate.exs — Quality gate for the task corpus.
#
# DEFAULT: perfect-score — every reference solution must grade a perfect overall of
# 1.0 (compiles with ZERO warnings, all tests pass, and full analysis: @moduledoc +
# @spec + @doc, no >98-char lines, no TODO/FIXME, no SQLi pattern). Reports the exact
# deductions per task and writes them to results/perfect_failures.txt.
#
# Opt-in lighter checks:
#   --green   reference-green only (compiles + tests pass; ignores analysis/warnings)
#   --fim     FIM mutation only (a raise-body mutant must make the parent harness fail)
#
# Concurrency defaults to min(16, schedulers-2); override with EVAL_CONCURRENCY=N.
#
# Usage: elixir scripts/validate.exs [--green] [--fim]

for pattern <- ["_build/dev/lib/*/ebin", "_build/test/lib/*/ebin"],
    path <- Path.wildcard(pattern) do
  Code.prepend_path(path)
end

defmodule Validate do
  @moduledoc false

  def main(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [green: :boolean, fim: :boolean])
    tasks = EvalTask.Discovery.all() |> Enum.filter(& &1.found)
    IO.puts("Concurrency: #{concurrency()} (EVAL_CONCURRENCY to override)")

    cond do
      opts[:green] ->
        f = reference_green(tasks)
        IO.puts("\n=== VALIDATION SUMMARY ===")
        report("reference-green", f)
        finish(f == [], "ALL GREEN ✓")

      opts[:fim] ->
        f = fim_mutation(tasks)
        IO.puts("\n=== VALIDATION SUMMARY ===")
        report("fim-mutation", f)
        finish(f == [], "ALL FIM TARGETS EXERCISED ✓")

      true ->
        failures = perfect_score(tasks)
        IO.puts("\n=== VALIDATION SUMMARY ===")
        report("perfect-score", failures)
        persist_failures(failures)
        finish(failures == [], "ALL PERFECT ✓ (every task scores 1.0)")
    end
  end

  defp finish(true, msg) do
    IO.puts("\n" <> msg)
    shutdown(0)
  end

  defp finish(false, _msg), do: shutdown(1)

  # `System.halt/1` terminates without flushing buffered stdout — under output
  # redirection (CI, `> log`) that drops the whole report. `System.stop/1` shuts
  # down gracefully (flushing stdio) and exits with the given code; we then block.
  defp shutdown(code) do
    System.stop(code)
    Process.sleep(:infinity)
  end

  defp persist_failures([]) do
    File.mkdir_p!("results")
    File.write!("results/perfect_failures.txt", "")
    :ok
  end

  defp persist_failures(failures) do
    File.mkdir_p!("results")
    path = "results/perfect_failures.txt"
    body = Enum.map_join(failures, "\n", fn {:fail, name, why} -> "#{name}\t#{why}" end)
    File.write!(path, body <> "\n")
    IO.puts("  (#{length(failures)} failures written to #{path})")
  end

  # ── perfect-score (default) ─────────────────────────────────────────────────

  # First pass grades every task in parallel. Suspects (sub-1.0) split by cause:
  # only a TEST failure can flake under parallel load, so only those are re-checked
  # (serially, unloaded); deterministic deductions (warnings, docs, line length)
  # never flake and are reported straight away.
  defp perfect_score(tasks) do
    IO.puts("Perfect-score: #{length(tasks)} tasks (overall must be 1.0) ...")

    {_perfect, suspects} =
      tasks
      |> pmap(fn task ->
        json = eval(task.dir, task.solution)
        ok? = perfect?(json)
        IO.write(if ok?, do: ".", else: "s")
        {task, json, ok?}
      end)
      |> Enum.split_with(fn {_t, _j, ok?} -> ok? end)

    {flaky_prone, deterministic} =
      Enum.split_with(suspects, fn {_t, json, _} -> test_failure?(json) end)

    if flaky_prone != [] do
      IO.puts("\nRe-checking #{length(flaky_prone)} test-failure suspects (flake filter) ...")
    end

    recovered =
      for {task, _j, _} <- flaky_prone, reduce: [] do
        acc ->
          json = eval(task.dir, task.solution)

          if perfect?(json) do
            IO.write("r")
            acc
          else
            IO.write("F")
            [failrec(task, json) | acc]
          end
      end

    Enum.reverse(recovered) ++ Enum.map(deterministic, fn {t, j, _} -> failrec(t, j) end)
  end

  defp failrec(task, json) do
    reasons = get_in(json, ["score", "reasons"]) || [describe(json)]
    overall = get_in(json, ["score", "overall"])
    {:fail, task.name, "overall=#{inspect(overall)} — #{Enum.join(reasons, "; ")}"}
  end

  defp perfect?(json) do
    overall = get_in(json, ["score", "overall"])
    is_number(overall) and overall >= 1.0
  end

  defp test_failure?(json) do
    (json["tests_failed"] || 0) > 0 or (json["tests_errors"] || 0) > 0
  end

  # ── opt-in lighter checks ───────────────────────────────────────────────────

  defp reference_green(tasks) do
    IO.puts("Reference-green: #{length(tasks)} tasks ...")

    tasks
    |> pmap(fn task ->
      json = eval(task.dir, task.solution)

      cond do
        Map.has_key?(json, "skipped") ->
          IO.write("s")
          nil

        json["compiled"] == true and json["tests_failed"] == 0 and
            (json["tests_errors"] || 0) == 0 and (json["tests_passed"] || 0) > 0 ->
          IO.write(".")
          nil

        true ->
          IO.write("F")
          {:fail, task.name, describe(json)}
      end
    end)
    |> collect()
  end

  defp fim_mutation(tasks) do
    fims = Enum.filter(tasks, &(&1.shape == :fim))
    IO.puts("FIM mutation: #{length(fims)} tasks ...")

    fims
    |> pmap(fn task ->
      mutant = mutant_file(task)
      json = eval(task.dir, mutant)
      File.rm(mutant)

      cond do
        json["compiled"] == true and (json["tests_failed"] || 0) > 0 ->
          IO.write(".")
          nil

        json["compiled"] != true ->
          IO.write("C")
          {:fail, task.name, "mutant did not COMPILE — coverage unverifiable"}

        true ->
          IO.write("U")
          {:fail, task.name, "mutant PASSED — target under-tested"}
      end
    end)
    |> collect()
  end

  defp mutant_file(task) do
    mutated = task.solution |> File.read!() |> EvalTask.Fim.mutate()
    path = Path.join(System.tmp_dir!(), "mutant_#{System.unique_integer([:positive])}.ex")
    File.write!(path, mutated)
    path
  end

  # ── shared ──────────────────────────────────────────────────────────────────

  defp eval(dir, solution) do
    case System.cmd("elixir", ["scripts/eval_task.exs", dir, solution], stderr_to_stdout: false) do
      {out, 0} ->
        out
        |> String.split("\n", trim: true)
        |> Enum.reverse()
        |> Enum.find("{}", &String.starts_with?(&1, "{"))
        |> Jason.decode!()

      {_, _} ->
        %{"compiled" => false, "tests_failed" => 0, "tests_total" => 0}
    end
  end

  defp describe(json) do
    cond do
      json["compiled"] != true ->
        "compile fail: #{inspect(get_in(json, ["compile_errors", Access.at(0), "message"]))}"

      true ->
        "#{json["tests_failed"]}/#{json["tests_total"]} failed"
    end
  end

  # Saturating worker pool (no chunk barrier) — keeps all cores busy. Each item is a
  # fresh eval_task.exs OS process, so concurrency ~= cores gives near-linear speedup.
  defp pmap(items, fun) do
    items
    |> Task.async_stream(fun,
      max_concurrency: concurrency(),
      timeout: :infinity,
      ordered: false
    )
    |> Enum.map(fn {:ok, r} -> r end)
  end

  defp concurrency do
    case System.get_env("EVAL_CONCURRENCY") do
      nil -> min(16, max(4, System.schedulers_online() - 2))
      v -> String.to_integer(v)
    end
  end

  defp collect(results), do: Enum.filter(results, &match?({:fail, _, _}, &1))

  defp report(label, []), do: IO.puts("  #{label}: all pass ✓")

  defp report(label, failures) do
    IO.puts("  #{label}: #{length(failures)} FAILED:")
    for {:fail, name, why} <- failures, do: IO.puts("    - #{name}: #{why}")
  end
end

Validate.main(System.argv())
