# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Pipeline do
  @moduledoc """
  Composable linear processing pipelines with per-stage retry policies.

  Each stage may declare a retry budget (`:retries`) and a backoff
  (`:backoff_ms`). A failing stage is re-invoked on the same input until it
  succeeds or the budget is exhausted. Timing is accumulated across attempts.
  """

  defstruct stages: []

  @type stage_fun :: (any() -> {:ok, any()} | {:error, any()})
  @type stage_meta :: %{
          stage: atom(),
          duration_us: non_neg_integer(),
          attempts: pos_integer()
        }
  @type t :: %__MODULE__{stages: [{atom(), stage_fun(), non_neg_integer(), non_neg_integer()}]}

  @doc "Returns a fresh, empty pipeline."
  @spec new() :: t()
  def new, do: %__MODULE__{stages: []}

  @doc """
  Appends a named stage with an optional retry policy.

  Options:
    * `:retries` — additional attempts after the first failure (default `0`)
    * `:backoff_ms` — milliseconds slept between attempts (default `0`)
  """
  @spec stage(t(), atom(), stage_fun(), keyword()) :: t()
  def stage(%__MODULE__{stages: stages} = pipeline, name, fun, opts \\ [])
      when is_atom(name) and is_function(fun, 1) and is_list(opts) do
    retries = Keyword.get(opts, :retries, 0)
    backoff = Keyword.get(opts, :backoff_ms, 0)
    %__MODULE__{pipeline | stages: stages ++ [{name, fun, retries, backoff}]}
  end

  @doc """
  Executes all stages in order, retrying failing stages per their policy.

  Returns `{:ok, final_result, metadata}` on full success, or
  `{:error, failed_stage, reason, attempts}` when a stage exhausts its budget.
  """
  @spec run(t(), any()) ::
          {:ok, any(), [stage_meta()]}
          | {:error, atom(), any(), pos_integer()}
  def run(%__MODULE__{stages: stages}, input) do
    execute(stages, input, [])
  end

  # ---------------------------------------------------------------------------

  defp execute([], value, meta_acc), do: {:ok, value, Enum.reverse(meta_acc)}

  defp execute([stage | rest], value, meta_acc) do
    case run_stage(stage, value) do
      {:ok, next_value, meta} -> execute(rest, next_value, [meta | meta_acc])
      {:error, name, reason, attempts} -> {:error, name, reason, attempts}
    end
  end

  defp run_stage({name, fun, retries, backoff}, value) do
    attempt(name, fun, value, retries, backoff, 0, 0)
  end

  defp attempt(name, fun, value, retries_left, backoff, attempts_before, dur_acc) do
    {duration, result} = :timer.tc(fn -> fun.(value) end)
    attempts = attempts_before + 1
    total_dur = dur_acc + duration

    case result do
      {:ok, next_value} ->
        {:ok, next_value, %{stage: name, duration_us: total_dur, attempts: attempts}}

      {:error, reason} ->
        if retries_left > 0 do
          if backoff > 0, do: Process.sleep(backoff)
          attempt(name, fun, value, retries_left - 1, backoff, attempts, total_dur)
        else
          {:error, name, reason, attempts}
        end

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
  use ExUnit.Case, async: false

  defp ok_stage(fun), do: fn input -> {:ok, fun.(input)} end
  defp always_fail(reason), do: fn _input -> {:error, reason} end

  test "new/0 returns a Pipeline struct" do
    assert %Pipeline{} = Pipeline.new()
  end

  test "empty pipeline returns input unchanged with empty metadata" do
    assert {:ok, 42, []} = Pipeline.run(Pipeline.new(), 42)
  end

  test "single successful stage with no retries has attempts: 1" do
    pipeline = Pipeline.new() |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))

    assert {:ok, 84, [%{stage: :double, attempts: 1, duration_us: d}]} =
             Pipeline.run(pipeline, 42)

    assert is_integer(d) and d >= 0
  end

  test "three stages thread results in order" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:add_one, ok_stage(&(&1 + 1)))
      |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))
      |> Pipeline.stage(:to_string, ok_stage(&Integer.to_string/1))

    assert {:ok, "10", metadata} = Pipeline.run(pipeline, 4)
    assert Enum.map(metadata, & &1.stage) == [:add_one, :double, :to_string]
    assert Enum.all?(metadata, &(&1.attempts == 1))
  end

  test "a flaky stage succeeds after retries and reports attempts" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)

    flaky = fn v ->
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 3, do: {:error, :flaky}, else: {:ok, v * 10}
    end

    pipeline = Pipeline.new() |> Pipeline.stage(:s, flaky, retries: 5)

    assert {:ok, 20, [%{stage: :s, attempts: 3}]} = Pipeline.run(pipeline, 2)
  end

  test "exhausting the retry budget halts with the attempts count" do
    pipeline = Pipeline.new() |> Pipeline.stage(:x, always_fail(:nope), retries: 2)
    assert {:error, :x, :nope, 3} = Pipeline.run(pipeline, 1)
  end

  test "default retries is zero (single attempt)" do
    pipeline = Pipeline.new() |> Pipeline.stage(:x, always_fail(:boom))
    assert {:error, :x, :boom, 1} = Pipeline.run(pipeline, 1)
  end

  test "stages after a permanently failing stage are never called" do
    {:ok, ran?} = Agent.start_link(fn -> false end)

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:fail, always_fail(:dead), retries: 1)
      |> Pipeline.stage(:next, fn v ->
        Agent.update(ran?, fn _ -> true end)
        {:ok, v}
      end)

    assert {:error, :fail, :dead, 2} = Pipeline.run(pipeline, 0)
    refute Agent.get(ran?, & &1)
  end

  test "duration accumulates across attempts" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)

    slow_flaky = fn v ->
      Process.sleep(5)
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 3, do: {:error, :retry}, else: {:ok, v}
    end

    pipeline = Pipeline.new() |> Pipeline.stage(:s, slow_flaky, retries: 5)

    assert {:ok, 7, [%{attempts: 3, duration_us: d}]} = Pipeline.run(pipeline, 7)
    # 3 attempts sleeping ~5ms each
    assert d >= 10_000
  end

  test "backoff option still succeeds within budget" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)

    flaky = fn v ->
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 2, do: {:error, :again}, else: {:ok, v + 1}
    end

    pipeline = Pipeline.new() |> Pipeline.stage(:s, flaky, retries: 3, backoff_ms: 2)
    assert {:ok, 6, [%{attempts: 2}]} = Pipeline.run(pipeline, 5)
  end

  test "only the failing stage is retried; earlier stages run once" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)

    first = fn v -> {:ok, v + 1} end

    flaky = fn v ->
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 2, do: {:error, :x}, else: {:ok, v}
    end

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:first, first)
      |> Pipeline.stage(:flaky, flaky, retries: 3)

    assert {:ok, 6, [%{stage: :first, attempts: 1}, %{stage: :flaky, attempts: 2}]} =
             Pipeline.run(pipeline, 5)
  end

  test "run/2 waits backoff_ms between attempts of a retried stage" do
    backoff_ms = 60
    retries = 2

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:x, always_fail(:nope), retries: retries, backoff_ms: backoff_ms)

    {elapsed_us, result} = :timer.tc(fn -> Pipeline.run(pipeline, 1) end)

    assert {:error, :x, :nope, 3} = result
    # 3 attempts of an instant function: the only time spent is the two
    # backoff sleeps that separate them.
    assert elapsed_us >= retries * backoff_ms * 1_000
  end

  test "backoff_ms is honoured before a retry that ultimately succeeds" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)
    backoff_ms = 60

    flaky = fn v ->
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 2, do: {:error, :again}, else: {:ok, v + 1}
    end

    pipeline =
      Pipeline.new() |> Pipeline.stage(:s, flaky, retries: 3, backoff_ms: backoff_ms)

    {elapsed_us, result} = :timer.tc(fn -> Pipeline.run(pipeline, 5) end)

    assert {:ok, 6, [%{stage: :s, attempts: 2}]} = result
    # Two attempts means exactly one backoff sleep separates them.
    assert elapsed_us >= backoff_ms * 1_000
  end

  test "every retry of a stage receives the identical original input" do
    {:ok, seen} = Agent.start_link(fn -> [] end)

    recorder = fn v ->
      n = Agent.get_and_update(seen, fn acc -> {length(acc) + 1, acc ++ [v]} end)
      if n < 4, do: {:error, :again}, else: {:ok, :done}
    end

    pipeline = Pipeline.new() |> Pipeline.stage(:rec, recorder, retries: 5)

    assert {:ok, :done, [%{stage: :rec, attempts: 4}]} =
             Pipeline.run(pipeline, {:payload, 99})

    assert Agent.get(seen, & &1) == List.duplicate({:payload, 99}, 4)
  end

  test "a stage that succeeds on a retry threads its result into the next stage" do
    # TODO
  end

  test "retries: 2 allows success on exactly the third and final permitted attempt" do
    {:ok, ag} = Agent.start_link(fn -> 0 end)

    flaky = fn v ->
      n = Agent.get_and_update(ag, fn c -> {c + 1, c + 1} end)
      if n < 3, do: {:error, :not_yet}, else: {:ok, v}
    end

    pipeline = Pipeline.new() |> Pipeline.stage(:edge, flaky, retries: 2)

    assert {:ok, :v, [%{stage: :edge, attempts: 3}]} = Pipeline.run(pipeline, :v)
  end

  test "a later stage failing reports its own name and only its own attempt count" do
    {:ok, firsts} = Agent.start_link(fn -> 0 end)

    first = fn v ->
      Agent.update(firsts, &(&1 + 1))
      {:ok, v}
    end

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:first, first, retries: 4)
      |> Pipeline.stage(:second, always_fail(:down), retries: 1)

    assert {:error, :second, :down, 2} = Pipeline.run(pipeline, :in)
    assert Agent.get(firsts, & &1) == 1
  end

  test "two stages registered under the same name both run in insertion order" do
    {:ok, ag} = Agent.start_link(fn -> [] end)

    step = fn tag ->
      fn v ->
        Agent.update(ag, &(&1 ++ [tag]))
        {:ok, v <> tag}
      end
    end

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:same, step.("a"))
      |> Pipeline.stage(:same, step.("b"))

    assert {:ok, "xab", [%{stage: :same}, %{stage: :same}]} = Pipeline.run(pipeline, "x")
    assert Agent.get(ag, & &1) == ["a", "b"]
  end

  test "stage/4 rejects a non-atom name and a function of the wrong arity" do
    pipeline = Pipeline.new()

    assert_raise FunctionClauseError, fn ->
      Pipeline.stage(pipeline, "not_an_atom", fn v -> {:ok, v} end)
    end

    assert_raise FunctionClauseError, fn ->
      Pipeline.stage(pipeline, :bad_arity, fn a, b -> {:ok, a + b} end)
    end
  end
end
```
