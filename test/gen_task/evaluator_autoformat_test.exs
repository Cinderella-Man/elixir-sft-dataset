defmodule GenTask.EvaluatorAutoformatTest do
  use ExUnit.Case, async: true

  alias GenTask.Evaluator

  test "formats solution.ex and test_harness.exs, leaves other keys alone" do
    files = %{
      "solution.ex" => "defmodule A do\n  def go( x ),   do: x\nend\n",
      "test_harness.exs" => "defmodule T do\n  def t, do:    :ok\nend\n",
      "prompt.md" => "#   Unformatted    prose stays"
    }

    out = Evaluator.autoformat(files)

    assert out["solution.ex"] == "defmodule A do\n  def go(x), do: x\nend\n"
    assert out["test_harness.exs"] == "defmodule T do\n  def t, do: :ok\nend\n"
    assert out["prompt.md"] == files["prompt.md"]
  end

  test "does not add parens to paren-less ExUnit macros" do
    src = """
    defmodule T do
      use ExUnit.Case

      test "x" do
        assert 1 == 1
        assert_receive {:fire, _}, 500
      end
    end
    """

    assert Evaluator.autoformat(%{"test_harness.exs" => src})["test_harness.exs"] == src
  end

  test "a file that does not parse passes through unchanged" do
    src = "defmodule Broken do\n  def oops(  do\nend\n"
    assert Evaluator.autoformat(%{"solution.ex" => src})["solution.ex"] == src
  end

  test "bundles are formatted per <file> part, wrapper bytes preserved" do
    bundle =
      "<file path=\"lib/a.ex\">\ndefmodule A do\n  def go( x ),   do: x\nend\n</file>\n" <>
        "<file path=\"lib/b.ex\">\ndefmodule B do\n  def ok, do: :ok\nend\n</file>"

    out = Evaluator.autoformat(%{"solution.ex" => bundle})["solution.ex"]

    assert out ==
             "<file path=\"lib/a.ex\">\ndefmodule A do\n  def go(x), do: x\nend\n</file>\n" <>
               "<file path=\"lib/b.ex\">\ndefmodule B do\n  def ok, do: :ok\nend\n</file>\n"
  end

  test "whole files gain a trailing newline when missing" do
    src = "defmodule A do\n  def go(x), do: x\nend"
    assert Evaluator.autoformat(%{"solution.ex" => src})["solution.ex"] == src <> "\n"
  end

  test "already-canonical input is byte-identical (idempotent)" do
    src = "defmodule A do\n  def go(x), do: x\nend\n"
    once = Evaluator.autoformat(%{"solution.ex" => src})["solution.ex"]
    assert once == src
    assert Evaluator.autoformat(%{"solution.ex" => once})["solution.ex"] == once
  end
end
