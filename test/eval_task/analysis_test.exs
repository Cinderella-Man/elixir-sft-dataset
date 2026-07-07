defmodule EvalTask.AnalysisTest do
  use ExUnit.Case, async: true
  alias EvalTask.Analysis

  @compiled %{compiled: true, compile_warnings: 0}
  @pass %{tests_passed: 10, tests_total: 10}

  @documented """
  defmodule A do
    @moduledoc "x"
    @doc "d"
    @spec go() :: :ok
    def go, do: :ok
  end
  """

  test "full analysis: a fully-documented, clean solution scores 1.0" do
    s = Analysis.score(@compiled, Analysis.analyze(@documented, :full), @pass)
    assert s.analysis == 1.0
    assert s.overall == 1.0
  end

  test "full analysis: missing docs/spec + a TODO deduct points (bug fixed)" do
    src = "defmodule A do\n  # TODO\n  def go, do: :ok\nend"
    s = Analysis.score(@compiled, Analysis.analyze(src, :full), @pass)
    # 8 max points; only 'no lines>98' + 'no SQLi' pass => 2/8 = 0.25
    assert s.analysis == 0.25
    assert Enum.any?(s.reasons, &(&1 =~ "@moduledoc"))
    assert Enum.any?(s.reasons, &(&1 =~ "TODO"))
  end

  test "fim mode drops moduledoc/spec/doc checks (max 3 points)" do
    s = Analysis.score(@compiled, Analysis.analyze("def go, do: :ok", :fim), @pass)
    assert s.analysis_max_points == 3
    assert s.analysis == 1.0
    assert s.mode == :fim
  end

  test "does-not-compile => overall 0.0" do
    s =
      Analysis.score(%{compiled: false, compile_warnings: 0}, Analysis.analyze("x", :full), @pass)

    assert s.overall == 0.0
    assert s.compilation == 0.0
  end

  test "weights: half the tests pass, full analysis, no warnings => 0.65" do
    s =
      Analysis.score(@compiled, Analysis.analyze(@documented, :full), %{
        tests_passed: 5,
        tests_total: 10
      })

    assert s.overall == 0.65
  end

  test "zero tests ran => overall 0.0 (no banking analysis+compilation points)" do
    s =
      Analysis.score(@compiled, Analysis.analyze(@documented, :full), %{
        tests_passed: 0,
        tests_total: 0
      })

    assert s.overall == 0.0
    assert Enum.any?(s.reasons, &(&1 =~ "no tests ran"))
  end

  test "harness errors => overall 0.0 even when counted tests passed" do
    s =
      Analysis.score(@compiled, Analysis.analyze(@documented, :full), %{
        tests_passed: 10,
        tests_total: 10,
        tests_errors: 2
      })

    assert s.overall == 0.0
    assert Enum.any?(s.reasons, &(&1 =~ "harness error"))
  end
end
