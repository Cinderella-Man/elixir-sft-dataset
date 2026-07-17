# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Pipeline do
  @moduledoc """
  Linear stage pipelines run over a batch of inputs.

  Each input item is threaded independently through the stages. A failing stage
  halts only that item (recording it as a failure); the batch continues with the
  remaining items. The final report separates successes from failures and
  aggregates per-stage execution counts and timing.

  Stage statistics are tracked per pipeline position, so two stages that share a
  name keep independent counters.
  """

  defstruct stages: []

  @type stage_fun :: (any() -> {:ok, any()} | {:error, any()})
  @type t :: %__MODULE__{stages: [{atom(), stage_fun()}]}

  @doc "Returns a fresh, empty pipeline."
  @spec new() :: t()
  def new, do: %__MODULE__{stages: []}

  @doc "Appends a named stage in insertion order."
  @spec stage(t(), atom(), stage_fun()) :: t()
  def stage(%__MODULE__{stages: stages} = pipeline, name, fun)
      when is_atom(name) and is_function(fun, 1) do
    %__MODULE__{pipeline | stages: stages ++ [{name, fun}]}
  end

  @doc """
  Runs every item in `inputs` independently through the pipeline, collecting a
  report of `:successes`, `:failures`, and per-stage `:stage_stats`.
  """
  @spec run(t(), [any()]) :: {:ok, map()}
  def run(%__MODULE__{stages: stages}, inputs) when is_list(inputs) do
    indexed_stages = Enum.with_index(stages)

    {successes, failures, stats} =
      inputs
      |> Enum.with_index()
      |> Enum.reduce({[], [], %{}}, fn {input, index}, {succ, fail, stats} ->
        case process_item(indexed_stages, input, stats) do
          {:ok, result, stats2} ->
            {[%{index: index, result: result} | succ], fail, stats2}

          {:error, name, reason, stats2} ->
            {succ, [%{index: index, stage: name, reason: reason} | fail], stats2}
        end
      end)

    stage_stats =
      Enum.map(indexed_stages, fn {{name, _fun}, position} ->
        stat_entry(name, position, stats)
      end)

    {:ok,
     %{
       successes: Enum.reverse(successes),
       failures: Enum.reverse(failures),
       stage_stats: stage_stats
     }}
  end

  # ---------------------------------------------------------------------------

  defp process_item([], value, stats), do: {:ok, value, stats}

  defp process_item([{{name, fun}, position} | rest], value, stats) do
    {duration, result} = :timer.tc(fn -> fun.(value) end)
    stats = bump(stats, position, duration)

    case result do
      {:ok, next_value} ->
        process_item(rest, next_value, stats)

      {:error, reason} ->
        {:error, name, reason, stats}

      other ->
        raise ArgumentError,
              "stage #{inspect(name)} returned an invalid value: #{inspect(other)}."
    end
  end

  defp bump(stats, position, duration) do
    Map.update(stats, position, {1, duration}, fn {count, total} ->
      {count + 1, total + duration}
    end)
  end

  defp stat_entry(name, position, stats) do
    {executions, total_duration_us} = Map.get(stats, position, {0, 0})
    %{stage: name, executions: executions, total_duration_us: total_duration_us}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule PipelineTest do
  use ExUnit.Case, async: false

  defp ok_stage(fun), do: fn input -> {:ok, fun.(input)} end

  test "new/0 returns a Pipeline struct" do
    # TODO
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

  test "duplicate stage names keep per-entry execution counts independent" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:same, ok_stage(&(&1 + 1)))
      |> Pipeline.stage(:same, ok_stage(&(&1 * 2)))

    assert {:ok, report} = Pipeline.run(pipeline, [1])

    assert report.successes == [%{index: 0, result: 4}]
    assert Enum.map(report.stage_stats, & &1.stage) == [:same, :same]
    assert Enum.map(report.stage_stats, & &1.executions) == [1, 1]
  end

  test "a halted item never invokes any later stage function" do
    parent = self()

    later = fn v ->
      send(parent, {:later_ran, v})
      {:ok, v}
    end

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:guard, fn v -> if v == :bomb, do: {:error, :boom}, else: {:ok, v} end)
      |> Pipeline.stage(:later, later)

    assert {:ok, report} = Pipeline.run(pipeline, [:bomb])

    assert report.failures == [%{index: 0, stage: :guard, reason: :boom}]
    assert report.successes == []
    refute_receive {:later_ran, _}, 50
  end

  test "multiple failures are listed in input index order" do
    guard = fn v -> if rem(v, 2) == 0, do: {:error, {:even, v}}, else: {:ok, v} end

    pipeline = Pipeline.new() |> Pipeline.stage(:parity, guard)

    assert {:ok, report} = Pipeline.run(pipeline, [2, 1, 4, 3, 6])

    assert report.failures == [
             %{index: 0, stage: :parity, reason: {:even, 2}},
             %{index: 2, stage: :parity, reason: {:even, 4}},
             %{index: 4, stage: :parity, reason: {:even, 6}}
           ]

    assert report.successes == [%{index: 1, result: 1}, %{index: 3, result: 3}]
  end

  test "stage/3 rejects a non-atom stage name" do
    assert_raise FunctionClauseError, fn ->
      Pipeline.stage(Pipeline.new(), "not_an_atom", ok_stage(& &1))
    end
  end

  test "stage/3 rejects a function whose arity is not one" do
    assert_raise FunctionClauseError, fn ->
      Pipeline.stage(Pipeline.new(), :bad_arity, fn a, b -> {:ok, {a, b}} end)
    end
  end

  test "run/2 rejects inputs that are not a list" do
    pipeline = Pipeline.new() |> Pipeline.stage(:noop, ok_stage(& &1))

    assert_raise FunctionClauseError, fn -> Pipeline.run(pipeline, :not_a_list) end
  end
end
```
