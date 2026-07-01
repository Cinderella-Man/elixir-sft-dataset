defmodule EvalTask.FimTest do
  use ExUnit.Case, async: true
  alias EvalTask.Fim

  test "parent_dir derives the _01 sibling" do
    assert Fim.parent_dir("tasks/001_001_rate_limiter_03") == "tasks/001_001_rate_limiter_01"
  end

  test "extract_candidate strips a wrapping elixir fence" do
    assert Fim.extract_candidate("```elixir\ndef x, do: 1\n```") == "def x, do: 1"
    assert Fim.extract_candidate("def x, do: 1") == "def x, do: 1"
  end

  test "splice replaces a stub-body def (# TODO inside)" do
    skeleton = "defmodule A do\n  def go(x) do\n    # TODO\n  end\nend"
    result = Fim.splice(skeleton, "  def go(x) do\n    x + 1\n  end")
    assert result =~ "x + 1"
    refute result =~ "# TODO"
    assert Code.string_to_quoted!(result)
  end

  test "splice replaces a placeholder line (#TODO funcname)" do
    skeleton = "defmodule A do\n  #TODO defp helper\nend"
    result = Fim.splice(skeleton, "  defp helper, do: :ok")
    assert result =~ "defp helper, do: :ok"
    refute result =~ "#TODO"
  end

  test "reconstruct uses a whole-module candidate verbatim" do
    prompt = "blah\n```elixir\ndefmodule A do\n  def go do\n    # TODO\n  end\nend\n```"
    whole = "defmodule A do\n  def go, do: :whole\nend"
    assert Fim.reconstruct(prompt, whole) == whole
  end

  test "mutate replaces every clause body with raise" do
    m = Fim.mutate("def a, do: 1\ndef b(x) do\n  x * 2\nend")
    assert m =~ ~s(raise "MUTATION")
    refute m =~ "x * 2"
  end
end
