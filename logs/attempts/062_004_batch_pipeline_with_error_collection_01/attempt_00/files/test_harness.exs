defmodule PipelineTest do
  use ExUnit.Case, async: false

  defp ok_stage(fun), do: fn input -> {:ok, fun.(input)} end

  test "new/0 returns a Pipeline struct" do
    assert %Pipeline{} = Pipeline.new()
  end

  test "empty pipeline reports every item as an identity success" do
    assert {:ok, report} = Pipeline.run(Pipeline.new(), [1, 2, 3])

    assert report.successes == [
             %{index: 0, result: 1},
             %{index: 1, result: 2},
             %{index: 2, result: 3}
           ]

    assert report.failures == []
    assert report.stage_stats == []
  end

  test "all items succeed and thread through stages" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:inc, ok_stage(&(&1 + 1)))
      |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))

    assert {:ok, report} = Pipeline.run(pipeline, [1, 2, 3])

    assert report.successes == [
             %{index: 0, result: 4},
             %{index: 1, result: 6},
             %{index: 2, result: 8}
           ]

    assert report.failures == []
    assert Enum.map(report.stage_stats, & &1.stage) == [:inc, :double]
    assert Enum.all?(report.stage_stats, &(&1.executions == 3))
  end

  test "a failing item is isolated; others still succeed" do
    guard = fn v -> if v == 3, do: {:error, :bad}, else: {:ok, v} end

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:inc, ok_stage(&(&1 + 1)))
      |> Pipeline.stage(:guard, guard)
      |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))

    assert {:ok, report} = Pipeline.run(pipeline, [1, 2, 3])

    # item0: 1->2->guard ok(2)->4 ; item1: 2->3->guard fails ; item2: 3->4->guard ok->8
    assert report.successes == [%{index: 0, result: 4}, %{index: 2, result: 8}]
    assert report.failures == [%{index: 1, stage: :guard, reason: :bad}]
  end

  test "stage_stats executions reflect early halting" do
    guard = fn v -> if v == 3, do: {:error, :bad}, else: {:ok, v} end

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:inc, ok_stage(&(&1 + 1)))
      |> Pipeline.stage(:guard, guard)
      |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))

    assert {:ok, report} = Pipeline.run(pipeline, [1, 2, 3])

    stats = Map.new(report.stage_stats, fn s -> {s.stage, s.executions} end)
    assert stats == %{inc: 3, guard: 3, double: 2}
  end

  test "empty inputs list yields zero executions per stage" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:a, ok_stage(& &1))
      |> Pipeline.stage(:b, ok_stage(& &1))

    assert {:ok, report} = Pipeline.run(pipeline, [])
    assert report.successes == []
    assert report.failures == []
    assert Enum.map(report.stage_stats, & &1.stage) == [:a, :b]
    assert Enum.all?(report.stage_stats, &(&1.executions == 0))
    assert Enum.all?(report.stage_stats, &(&1.total_duration_us == 0))
  end

  test "stage_stats are ordered by pipeline stage order" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:alpha, ok_stage(& &1))
      |> Pipeline.stage(:beta, ok_stage(& &1))
      |> Pipeline.stage(:gamma, ok_stage(& &1))

    assert {:ok, report} = Pipeline.run(pipeline, [:x])
    assert Enum.map(report.stage_stats, & &1.stage) == [:alpha, :beta, :gamma]
  end

  test "total_duration_us accumulates across items" do
    slow =
      fn v ->
        Process.sleep(5)
        {:ok, v}
      end

    pipeline = Pipeline.new() |> Pipeline.stage(:slow, slow)

    assert {:ok, report} = Pipeline.run(pipeline, [1, 1])
    [%{stage: :slow, executions: 2, total_duration_us: d}] = report.stage_stats
    assert d >= 8_000
  end

  test "an item failing at the first stage records that stage" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:first, fn _ -> {:error, :nope} end)
      |> Pipeline.stage(:second, ok_stage(& &1))

    assert {:ok, report} = Pipeline.run(pipeline, [42])
    assert report.successes == []
    assert report.failures == [%{index: 0, stage: :first, reason: :nope}]

    stats = Map.new(report.stage_stats, fn s -> {s.stage, s.executions} end)
    assert stats == %{first: 1, second: 0}
  end
end