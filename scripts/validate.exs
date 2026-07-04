#!/usr/bin/env elixir
# validate.exs — Quality gate for the task corpus (T8 / FIM-T4).
#
#   1. Reference-green: run every found reference solution through eval_task.exs
#      and assert it is green (or an allowed SKIP, e.g. db: :postgres). Catches
#      harness bugs that compile-only checks miss (e.g. task 021's dead-code line).
#   2. FIM mutation: for each FIM, splice a `raise`-body mutant and assert the
#      parent harness now FAILS. A mutant that passes = an under-tested target.
#
# Usage: elixir scripts/validate.exs [--fim-only] [--green-only]

for pattern <- ["_build/dev/lib/*/ebin", "_build/test/lib/*/ebin"],
    path <- Path.wildcard(pattern) do
  Code.prepend_path(path)
end

defmodule Validate do
  @moduledoc false

  def main(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [fim_only: :boolean, green_only: :boolean])
    tasks = EvalTask.Discovery.all() |> Enum.filter(& &1.found)

    green_failures =
      if opts[:green_only] || !opts[:fim_only], do: reference_green(tasks), else: []

    mutation_failures =
      if opts[:fim_only] || !opts[:green_only], do: fim_mutation(tasks), else: []

    IO.puts("\n=== VALIDATION SUMMARY ===")
    report("reference-green", green_failures)
    report("fim-mutation", mutation_failures)

    if green_failures == [] and mutation_failures == [] do
      IO.puts("\nALL GREEN ✓")
      System.halt(0)
    else
      System.halt(1)
    end
  end

  defp reference_green(tasks) do
    IO.puts("Reference-green: #{length(tasks)} tasks ...")

    tasks
    |> parallel_map(fn task ->
      json = eval(task.dir, task.solution)

      cond do
        Map.has_key?(json, "skipped") ->
          IO.write("s")

        # Same bar as GenTask.Evaluator.green?/1: at least one test must have RUN
        # and passed (all-@tag-:skip harnesses report tests_total > 0 with zero
        # passed), and harness-load errors (tests_errors) fail too.
        json["compiled"] == true and json["tests_failed"] == 0 and
          (json["tests_errors"] || 0) == 0 and (json["tests_passed"] || 0) > 0 ->
          IO.write(".")

        true ->
          IO.write("F")
          {:fail, task.name, describe(json)}
      end
    end)
    |> collect()
  end

  defp fim_mutation(tasks) do
    fims = Enum.filter(tasks, &(&1.shape == :fim))
    IO.puts("\nFIM mutation: #{length(fims)} tasks ...")

    fims
    |> parallel_map(fn task ->
      mutant = mutant_file(task)
      json = eval(task.dir, mutant)
      File.rm(mutant)
      # A raise-body mutant MUST make the harness RUN and fail. A mutant that does
      # not compile proves nothing about coverage (docs/05 #18) — the harness never
      # observed it — so it is reported as a distinct failure, not counted exercised.
      cond do
        json["compiled"] == true and (json["tests_failed"] || 0) > 0 ->
          IO.write(".")

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
    candidate = File.read!(task.solution)
    mutated = EvalTask.Fim.mutate(candidate)
    path = Path.join(System.tmp_dir!(), "mutant_#{System.unique_integer([:positive])}.ex")
    File.write!(path, mutated)
    path
  end

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

  defp parallel_map(items, fun) do
    items
    |> Enum.chunk_every(6)
    |> Enum.flat_map(fn chunk ->
      chunk |> Enum.map(&Task.async(fn -> fun.(&1) end)) |> Task.await_many(:infinity)
    end)
  end

  defp collect(results), do: Enum.filter(results, &match?({:fail, _, _}, &1))

  defp report(label, []), do: IO.puts("  #{label}: all pass ✓")

  defp report(label, failures) do
    IO.puts("  #{label}: #{length(failures)} FAILED:")
    for {:fail, name, why} <- failures, do: IO.puts("    - #{name}: #{why}")
  end
end

Validate.main(System.argv())
