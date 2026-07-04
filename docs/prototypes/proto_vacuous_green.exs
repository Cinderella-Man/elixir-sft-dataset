# Demonstrate §6.1#1: an all-@tag :skip harness grades "green" per Evaluator.green?/1
scratch = Path.join(System.tmp_dir!(), "vacuous_proto")
File.rm_rf!(scratch)
dir = Path.join(scratch, "999_001_vacuous_01")
File.mkdir_p!(dir)

File.write!(Path.join(dir, "solution.ex"), """
defmodule Vacuous do
  @moduledoc "Does nothing."
  @doc "Returns :ok."
  @spec go() :: :ok
  def go, do: :ok
end
""")

File.write!(Path.join(dir, "test_harness.exs"), """
defmodule VacuousTest do
  use ExUnit.Case, async: true

  @tag :skip
  test "never runs but claims coverage" do
    assert Vacuous.go() == :nope
  end

  @tag :skip
  test "also never runs" do
    assert 1 == 2
  end
end
""")

{out, _} =
  System.cmd("elixir", [Path.join(File.cwd!(), "scripts/eval_task.exs"), dir],
    cd: File.cwd!(), stderr_to_stdout: true)

json = out |> String.split("\n", trim: true) |> List.last() |> Jason.decode!()

IO.puts("eval JSON: total=#{json["tests_total"]} passed=#{json["tests_passed"]} " <>
  "failed=#{json["tests_failed"]} errors=#{json["tests_errors"]} " <>
  "excluded=#{json["tests_excluded"]} overall=#{json["score"]["overall"]}")

green = GenTask.Evaluator.green?({:ok, json})
IO.puts("GenTask.Evaluator.green?/1 says: #{green}  (both asserts are FALSE and never ran)")
IO.puts(if green, do: "BUG DEMONSTRATED: vacuous harness would be ACCEPTED", else: "not reproduced")
