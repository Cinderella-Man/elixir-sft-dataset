# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Pipeline do
  @moduledoc """
  Composable linear processing pipelines.

  Stages are executed in insertion order, each receiving the previous stage's
  result as input. Timing metadata (in microseconds) is collected for every
  stage that actually runs.

  ## Example

      iex> Pipeline.new()
      ...> |> Pipeline.stage(:parse,    fn s -> {:ok, String.to_integer(s)} end)
      ...> |> Pipeline.stage(:double,   fn n -> {:ok, n * 2} end)
      ...> |> Pipeline.stage(:to_str,   fn n -> {:ok, Integer.to_string(n)} end)
      ...> |> Pipeline.run("21")
      {:ok, "42", [
        %{stage: :parse,   duration_us: ...},
        %{stage: :double,  duration_us: ...},
        %{stage: :to_str,  duration_us: ...}
      ]}
  """

  @enforce_keys [:stages]
  defstruct stages: []

  @type stage_meta :: %{stage: atom(), duration_us: non_neg_integer()}

  @type t :: %__MODULE__{
          stages: [{atom(), (any() -> {:ok, any()} | {:error, any()})}]
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Returns a fresh, empty pipeline."
  @spec new() :: t()
  def new, do: %__MODULE__{stages: []}

  @doc """
  Appends a named stage to the pipeline.

  `fun` must be a one-arity function that returns either
  `{:ok, result}` or `{:error, reason}`.
  """
  @spec stage(t(), atom(), (any() -> {:ok, any()} | {:error, any()})) :: t()
  def stage(%__MODULE__{stages: stages} = pipeline, name, fun)
      when is_atom(name) and is_function(fun, 1) do
    %__MODULE__{pipeline | stages: stages ++ [{name, fun}]}
  end

  @doc """
  Executes all stages in insertion order, threading results through the chain.

  Returns:
  - `{:ok, final_result, [%{stage: atom, duration_us: non_neg_integer}]}` — all stages passed.
  - `{:error, failed_stage, reason}` — a stage failed; subsequent stages are skipped.

  Timing is measured with `:timer.tc/1` around every stage invocation, but
  metadata travels only in the success tuple — the error result carries no
  metadata list, so a failed run discards the timings collected so far.
  """
  @spec run(t(), any()) ::
          {:ok, any(), [stage_meta()]}
          | {:error, atom(), any()}
  def run(%__MODULE__{stages: stages}, input) do
    execute(stages, input, [])
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Base case — all stages completed successfully.
  defp execute([], value, meta_acc) do
    {:ok, value, Enum.reverse(meta_acc)}
  end

  defp execute([{name, fun} | rest], value, meta_acc) do
    {duration_us, result} = :timer.tc(fn -> fun.(value) end)
    meta = %{stage: name, duration_us: duration_us}

    case result do
      {:ok, next_value} ->
        execute(rest, next_value, [meta | meta_acc])

      {:error, reason} ->
        # The contract's halt result is exactly three elements with no
        # metadata list — the timings accumulated so far are dropped.
        {:error, name, reason}

      other ->
        raise ArgumentError,
              "stage #{inspect(name)} returned an invalid value: #{inspect(other)}. " <>
                "Expected {:ok, result} or {:error, reason}."
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule PipelineTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp ok_stage(fun), do: fn input -> {:ok, fun.(input)} end
  defp fail_stage(reason), do: fn _input -> {:error, reason} end

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  test "new/0 returns an empty pipeline" do
    pipeline = Pipeline.new()
    assert %Pipeline{} = pipeline
  end

  test "stage/3 returns a Pipeline struct" do
    pipeline = Pipeline.new() |> Pipeline.stage(:first, ok_stage(& &1))
    assert %Pipeline{} = pipeline
  end

  # ---------------------------------------------------------------------------
  # All-success pipelines
  # ---------------------------------------------------------------------------

  test "single stage runs and returns ok with metadata" do
    pipeline = Pipeline.new() |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))

    assert {:ok, 84, metadata} = Pipeline.run(pipeline, 42)
    assert length(metadata) == 1
    assert [%{stage: :double, duration_us: d}] = metadata
    assert is_integer(d) and d >= 0
  end

  test "three stages thread results correctly" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:add_one, ok_stage(&(&1 + 1)))
      |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))
      |> Pipeline.stage(:to_string, ok_stage(&Integer.to_string/1))

    assert {:ok, "10", metadata} = Pipeline.run(pipeline, 4)
    assert length(metadata) == 3
    assert Enum.map(metadata, & &1.stage) == [:add_one, :double, :to_string]
    assert Enum.all?(metadata, &is_integer(&1.duration_us))
    assert Enum.all?(metadata, &(&1.duration_us >= 0))
  end

  test "pipeline with no stages returns input unchanged" do
    assert {:ok, 99, []} = Pipeline.run(Pipeline.new(), 99)
  end

  test "stages receive exactly the previous stage's output" do
    acc = Agent.start_link(fn -> [] end) |> elem(1)

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:one, fn v ->
        Agent.update(acc, &[v | &1])
        {:ok, v + 10}
      end)
      |> Pipeline.stage(:two, fn v ->
        Agent.update(acc, &[v | &1])
        {:ok, v + 10}
      end)
      |> Pipeline.stage(:three, fn v ->
        Agent.update(acc, &[v | &1])
        {:ok, v + 10}
      end)

    assert {:ok, 30, _} = Pipeline.run(pipeline, 0)
    assert Enum.reverse(Agent.get(acc, & &1)) == [0, 10, 20]
  end

  # ---------------------------------------------------------------------------
  # Failing stage — halt and error tuple
  # ---------------------------------------------------------------------------

  test "first stage failing returns error with correct stage name and reason" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:fetch, fail_stage(:timeout))
      |> Pipeline.stage(:transform, ok_stage(& &1))

    assert {:error, :fetch, :timeout} = Pipeline.run(pipeline, "input")
  end

  test "middle stage failing halts and returns correct stage name" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:fetch, ok_stage(&(&1 <> "_fetched")))
      |> Pipeline.stage(:transform, fail_stage(:bad_data))
      |> Pipeline.stage(:load, ok_stage(&(&1 <> "_loaded")))

    assert {:error, :transform, :bad_data} = Pipeline.run(pipeline, "x")
  end

  test "last stage failing returns error tuple" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:a, ok_stage(& &1))
      |> Pipeline.stage(:b, ok_stage(& &1))
      |> Pipeline.stage(:c, fail_stage(:disk_full))

    assert {:error, :c, :disk_full} = Pipeline.run(pipeline, 0)
  end

  test "stages after a failing one are never called" do
    called = Agent.start_link(fn -> false end) |> elem(1)

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:fail, fail_stage(:boom))
      |> Pipeline.stage(:should_not_run, fn v ->
        Agent.update(called, fn _ -> true end)
        {:ok, v}
      end)

    Pipeline.run(pipeline, nil)
    refute Agent.get(called, & &1)
  end

  # ---------------------------------------------------------------------------
  # Metadata on partial run
  # ---------------------------------------------------------------------------

  test "metadata only includes executed stages when pipeline halts early" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:step_one, ok_stage(& &1))
      |> Pipeline.stage(:step_two, fail_stage(:nope))
      |> Pipeline.stage(:step_three, ok_stage(& &1))

    # On error we don't return metadata, so just verify halt behaviour
    assert {:error, :step_two, :nope} = Pipeline.run(pipeline, 1)
  end

  test "successful metadata entries are ordered by execution" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:alpha, ok_stage(& &1))
      |> Pipeline.stage(:beta, ok_stage(& &1))
      |> Pipeline.stage(:gamma, ok_stage(& &1))

    assert {:ok, _, metadata} = Pipeline.run(pipeline, :val)
    assert Enum.map(metadata, & &1.stage) == [:alpha, :beta, :gamma]
  end

  # ---------------------------------------------------------------------------
  # Timing sanity
  # ---------------------------------------------------------------------------

  test "a stage that sleeps produces a duration_us greater than sleep time" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:slow, fn v ->
        Process.sleep(10)
        {:ok, v}
      end)

    assert {:ok, _, [%{stage: :slow, duration_us: d}]} = Pipeline.run(pipeline, 1)
    # 10 ms = 10_000 µs; allow a small margin
    assert d >= 9_000
  end

  # ---------------------------------------------------------------------------
  # Works with various input types
  # ---------------------------------------------------------------------------

  test "pipeline works with map input and output" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:enrich, ok_stage(&Map.put(&1, :enriched, true)))
      |> Pipeline.stage(:serialize, ok_stage(&Map.keys/1))

    assert {:ok, keys, _} = Pipeline.run(pipeline, %{a: 1})
    assert :enriched in keys
  end

  test "pipeline works with list input" do
    # TODO
  end

  test "halted run still reports timing metadata for the stages that actually executed" do
    executed = Agent.start_link(fn -> [] end) |> elem(1)

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:first, fn v ->
        Agent.update(executed, &[:first | &1])
        {:ok, v}
      end)
      |> Pipeline.stage(:boom, fn _ ->
        Agent.update(executed, &[:boom | &1])
        {:error, :nope}
      end)
      |> Pipeline.stage(:never, fn v ->
        Agent.update(executed, &[:never | &1])
        {:ok, v}
      end)

    # A halted run reports the failing stage and its reason; per the public
    # contract the error tuple carries no metadata list.
    assert {:error, :boom, :nope} = Pipeline.run(pipeline, 1)
    assert Enum.reverse(Agent.get(executed, & &1)) == [:first, :boom]

    # The same executed prefix, run to completion, reports timing for exactly
    # those stages and nothing more.
    prefix =
      Pipeline.new()
      |> Pipeline.stage(:first, fn v -> {:ok, v} end)
      |> Pipeline.stage(:boom, fn v -> {:ok, v} end)

    assert {:ok, 1, metadata} = Pipeline.run(prefix, 1)
    assert Enum.map(metadata, & &1.stage) == [:first, :boom]
    assert Enum.all?(metadata, &(is_integer(&1.duration_us) and &1.duration_us >= 0))
  end

  test "stages execute in the calling process and repeated runs are unaffected by prior runs" do
    caller = self()

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:report, fn v ->
        send(caller, {:ran_in, self()})
        {:ok, v + 1}
      end)
      |> Pipeline.stage(:finish, fn v -> {:ok, v * 2} end)

    assert {:ok, 4, meta_one} = Pipeline.run(pipeline, 1)
    assert_receive {:ran_in, ^caller}, 100

    assert {:ok, 4, meta_two} = Pipeline.run(pipeline, 1)
    assert_receive {:ran_in, ^caller}, 100

    assert Enum.map(meta_one, & &1.stage) == Enum.map(meta_two, & &1.stage)
    refute_receive {:ran_in, _}, 50
  end

  test "stage/3 rejects a non-atom name and a function of the wrong arity" do
    pipeline = Pipeline.new()

    assert_raise FunctionClauseError, fn ->
      Pipeline.stage(pipeline, "not_an_atom", fn v -> {:ok, v} end)
    end

    assert_raise FunctionClauseError, fn ->
      Pipeline.stage(pipeline, :two_arity, fn a, b -> {:ok, {a, b}} end)
    end
  end

  test "duplicate stage names both run in insertion order and the failing one is named" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:step, fn v -> {:ok, v <> "a"} end)
      |> Pipeline.stage(:step, fn v -> {:ok, v <> "b"} end)

    assert {:ok, "xab", metadata} = Pipeline.run(pipeline, "x")
    assert Enum.map(metadata, & &1.stage) == [:step, :step]

    failing =
      Pipeline.new()
      |> Pipeline.stage(:step, fn v -> {:ok, v} end)
      |> Pipeline.stage(:step, fn _ -> {:error, :second} end)

    assert {:error, :step, :second} = Pipeline.run(failing, "x")
  end

  test "stage/3 leaves the original pipeline untouched so a base can be reused" do
    base = Pipeline.new() |> Pipeline.stage(:base, fn v -> {:ok, v + 1} end)

    left = Pipeline.stage(base, :left, fn v -> {:ok, v * 10} end)
    right = Pipeline.stage(base, :right, fn v -> {:ok, v * 100} end)

    assert {:ok, 2, base_meta} = Pipeline.run(base, 1)
    assert Enum.map(base_meta, & &1.stage) == [:base]

    assert {:ok, 20, left_meta} = Pipeline.run(left, 1)
    assert Enum.map(left_meta, & &1.stage) == [:base, :left]

    assert {:ok, 200, right_meta} = Pipeline.run(right, 1)
    assert Enum.map(right_meta, & &1.stage) == [:base, :right]
  end

  test "the failure reason term is returned verbatim regardless of its shape" do
    reason = {:http, 500, %{body: "boom", retries: [1, 2]}}

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:fetch, fn _ -> {:error, reason} end)

    assert {:error, :fetch, ^reason} = Pipeline.run(pipeline, :input)
  end
end
```
