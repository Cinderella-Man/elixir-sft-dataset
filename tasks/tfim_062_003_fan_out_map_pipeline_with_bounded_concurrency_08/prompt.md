# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Pipeline do
  @moduledoc """
  Composable linear pipelines with concurrent fan-out (`map`) stages.

  Sequential stages thread a single value; a `map_stage/4` applies a function
  to each element of a list concurrently (bounded by `:max_concurrency`),
  collecting results in input order and failing on the first failing element.
  """

  defstruct stages: []

  @type stage_fun :: (any() -> {:ok, any()} | {:error, any()})
  @type t :: %__MODULE__{stages: list()}

  @doc "Returns a fresh, empty pipeline."
  @spec new() :: t()
  def new, do: %__MODULE__{stages: []}

  @doc "Appends a sequential stage."
  @spec stage(t(), atom(), stage_fun()) :: t()
  def stage(%__MODULE__{stages: stages} = pipeline, name, fun)
      when is_atom(name) and is_function(fun, 1) do
    %__MODULE__{pipeline | stages: stages ++ [{:seq, name, fun}]}
  end

  @doc """
  Appends a fan-out map stage. Its input must be a list; `fun` is applied to
  each element concurrently. Option `:max_concurrency` bounds parallelism.
  """
  @spec map_stage(t(), atom(), stage_fun(), keyword()) :: t()
  def map_stage(%__MODULE__{stages: stages} = pipeline, name, fun, opts \\ [])
      when is_atom(name) and is_function(fun, 1) and is_list(opts) do
    mc = Keyword.get(opts, :max_concurrency, nil)
    %__MODULE__{pipeline | stages: stages ++ [{:map, name, fun, mc}]}
  end

  @doc """
  Runs all stages in order. Returns `{:ok, final, metadata}` or
  `{:error, failed_stage, reason}`.
  """
  @spec run(t(), any()) ::
          {:ok, any(), [map()]} | {:error, atom(), any()}
  def run(%__MODULE__{stages: stages}, input) do
    execute(stages, input, [])
  end

  # ---------------------------------------------------------------------------

  defp execute([], value, meta_acc), do: {:ok, value, Enum.reverse(meta_acc)}

  defp execute([stage | rest], value, meta_acc) do
    case run_stage(stage, value) do
      {:ok, next_value, meta} -> execute(rest, next_value, [meta | meta_acc])
      {:error, name, reason} -> {:error, name, reason}
    end
  end

  defp run_stage({:seq, name, fun}, value) do
    {duration, result} = :timer.tc(fn -> fun.(value) end)

    case result do
      {:ok, next_value} ->
        {:ok, next_value, %{stage: name, duration_us: duration, type: :sequential, count: 1}}

      {:error, reason} ->
        {:error, name, reason}

      other ->
        raise ArgumentError,
              "stage #{inspect(name)} returned an invalid value: #{inspect(other)}."
    end
  end

  defp run_stage({:map, name, fun, mc_opt}, value) do
    unless is_list(value) do
      raise ArgumentError,
            "map stage #{inspect(name)} requires a list input, got: #{inspect(value)}"
    end

    count = length(value)
    max_concurrency = mc_opt || max(count, 1)

    {duration, results} =
      :timer.tc(fn ->
        value
        |> Task.async_stream(fun,
          max_concurrency: max_concurrency,
          ordered: true,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, element_result} -> element_result end)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        outputs = Enum.map(results, fn {:ok, v} -> v end)
        {:ok, outputs, %{stage: name, duration_us: duration, type: :map, count: count}}

      {:error, reason} ->
        {:error, name, reason}
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule PipelineTest do
  use ExUnit.Case, async: false

  defp ok_stage(fun), do: fn input -> {:ok, fun.(input)} end

  test "new/0 returns a Pipeline struct" do
    assert %Pipeline{} = Pipeline.new()
  end

  test "empty pipeline returns input unchanged" do
    assert {:ok, 5, []} = Pipeline.run(Pipeline.new(), 5)
  end

  test "sequential stages thread and report :sequential metadata" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:add, ok_stage(&(&1 + 1)))
      |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))

    assert {:ok, 10, metadata} = Pipeline.run(pipeline, 4)
    assert Enum.map(metadata, & &1.stage) == [:add, :double]
    assert Enum.all?(metadata, &(&1.type == :sequential and &1.count == 1))
  end

  test "map stage processes every element and threads a list forward" do
    pipeline =
      Pipeline.new()
      |> Pipeline.map_stage(:double_each, fn x -> {:ok, x * 2} end)
      |> Pipeline.stage(:sum, ok_stage(&Enum.sum/1))

    assert {:ok, 12, metadata} = Pipeline.run(pipeline, [1, 2, 3])
    assert [%{stage: :double_each, type: :map, count: 3}, %{stage: :sum, type: :sequential}] =
             metadata
  end

  test "map stage preserves input order in its output" do
    pipeline =
      Pipeline.new()
      |> Pipeline.map_stage(:id, fn x -> {:ok, x} end)

    assert {:ok, [5, 3, 9, 1], _} = Pipeline.run(pipeline, [5, 3, 9, 1])
  end

  test "map stage fails on the first failing element by index" do
    fail_on_three = fn x -> if x == 3, do: {:error, :three}, else: {:ok, x} end

    pipeline = Pipeline.new() |> Pipeline.map_stage(:check, fail_on_three)

    assert {:error, :check, :three} = Pipeline.run(pipeline, [1, 2, 3, 4])
  end

  test "stages after a failing map stage never run" do
    # TODO
  end

  test "map stage runs elements concurrently" do
    slow = fn x ->
      Process.sleep(20)
      {:ok, x}
    end

    pipeline =
      Pipeline.new()
      |> Pipeline.map_stage(:slow, slow, max_concurrency: 4)

    assert {:ok, [1, 2, 3, 4], [%{stage: :slow, duration_us: d}]} =
             Pipeline.run(pipeline, [1, 2, 3, 4])

    # 4 * 20ms serial would be ~80ms; concurrent should be far below.
    assert d < 90_000
  end

  test "max_concurrency: 1 serializes element processing" do
    slow = fn x ->
      Process.sleep(20)
      {:ok, x}
    end

    pipeline =
      Pipeline.new()
      |> Pipeline.map_stage(:slow, slow, max_concurrency: 1)

    assert {:ok, _, [%{stage: :slow, duration_us: d}]} = Pipeline.run(pipeline, [1, 2, 3])
    assert d >= 30_000
  end

  test "map stage on empty list yields empty output" do
    pipeline = Pipeline.new() |> Pipeline.map_stage(:m, fn x -> {:ok, x} end)
    assert {:ok, [], [%{stage: :m, type: :map, count: 0}]} = Pipeline.run(pipeline, [])
  end

  test "map stage with non-list input raises ArgumentError" do
    pipeline = Pipeline.new() |> Pipeline.map_stage(:m, fn x -> {:ok, x} end)

    assert_raise ArgumentError, fn ->
      Pipeline.run(pipeline, :not_a_list)
    end
  end

  test "a failing sequential stage halts with a 3-tuple error" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:a, ok_stage(& &1))
      |> Pipeline.stage(:b, fn _ -> {:error, :boom} end)

    assert {:error, :b, :boom} = Pipeline.run(pipeline, 0)
  end
end
```
