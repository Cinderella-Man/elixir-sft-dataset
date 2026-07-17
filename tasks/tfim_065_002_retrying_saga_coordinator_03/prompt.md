# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule RetrySaga do
  @moduledoc """
  A saga / compensating-transaction coordinator with **bounded retries** on each
  step's forward action.

  Steps run in order. A step's action may be retried up to `:max_attempts` times
  (default 1). Only when all attempts return `{:error, _}` is the step considered
  failed, at which point the compensations of previously-completed steps are run in
  reverse completion order (best-effort).
  """

  @opaque t :: %__MODULE__{steps: [step()]}
  @type context :: map()
  @type step :: %{
          name: term(),
          action: (context() -> {:ok, term()} | {:error, term()}),
          compensation: (context() -> term()),
          max_attempts: pos_integer()
        }
  @type error :: %{
          step: term(),
          error: term(),
          attempts: pos_integer(),
          compensated: [term()],
          compensations: %{optional(term()) => term()}
        }

  defstruct steps: []

  @doc "Returns a new, empty saga."
  @spec new() :: t()
  def new, do: %__MODULE__{steps: []}

  @doc """
  Appends a step. `opts` supports `:max_attempts` (a positive integer, default 1).
  """
  @spec step(
          t(),
          term(),
          (context() -> {:ok, term()} | {:error, term()}),
          (context() -> term()),
          keyword()
        ) :: t()
  def step(%__MODULE__{steps: steps} = saga, name, action, compensation, opts \\ [])
      when is_function(action, 1) and is_function(compensation, 1) do
    max_attempts = Keyword.get(opts, :max_attempts, 1)

    unless is_integer(max_attempts) and max_attempts >= 1 do
      raise ArgumentError,
            "max_attempts must be a positive integer, got: #{inspect(max_attempts)}"
    end

    step = %{name: name, action: action, compensation: compensation, max_attempts: max_attempts}
    %__MODULE__{saga | steps: steps ++ [step]}
  end

  @doc "Runs the saga from `context`."
  @spec execute(t(), context()) :: {:ok, context()} | {:error, error()}
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    forward(steps, context, [])
  end

  # `completed` is in reverse completion order (most recent first).
  defp forward([], context, _completed), do: {:ok, context}

  defp forward([step | rest], context, completed) do
    case run_action(step, context, 1) do
      {:ok, result} ->
        forward(rest, Map.put(context, step.name, result), [step | completed])

      {:error, reason, attempts} ->
        compensate(completed, context, step.name, reason, attempts)
    end
  end

  defp run_action(step, context, attempt) do
    case step.action.(context) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        if attempt < step.max_attempts do
          run_action(step, context, attempt + 1)
        else
          {:error, reason, attempt}
        end
    end
  end

  defp compensate(completed, context, failed_step, reason, attempts) do
    {compensated, compensations} =
      Enum.reduce(completed, {[], %{}}, fn %{name: name, compensation: comp}, {names, results} ->
        result = comp.(context)
        {[name | names], Map.put(results, name, result)}
      end)

    {:error,
     %{
       step: failed_step,
       error: reason,
       attempts: attempts,
       compensated: Enum.reverse(compensated),
       compensations: compensations
     }}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule RetrySagaTest do
  use ExUnit.Case, async: false

  defmodule Recorder do
    use Agent

    def start_link(_ \\ nil), do: Agent.start_link(fn -> [] end, name: __MODULE__)
    def record(event), do: Agent.update(__MODULE__, &[event | &1])
    def events, do: Agent.get(__MODULE__, &Enum.reverse(&1))
    def actions(name), do: Enum.count(events(), &(&1 == {:action, name}))
  end

  setup do
    start_supervised!(Recorder)
    :ok
  end

  # An action that fails `fail_times` times (recording each attempt), then succeeds.
  defp flaky_action(name, fail_times, result) do
    {:ok, pid} = Agent.start_link(fn -> 0 end)

    fn _ctx ->
      n = Agent.get_and_update(pid, fn c -> {c + 1, c + 1} end)
      Recorder.record({:action, name})
      if n <= fail_times, do: {:error, {:attempt, n}}, else: {:ok, result}
    end
  end

  defp always_fail(name, reason) do
    fn _ctx ->
      Recorder.record({:action, name})
      {:error, reason}
    end
  end

  defp comp(name, ret \\ {:ok, :compensated}) do
    fn _ctx ->
      Recorder.record({:comp, name})
      ret
    end
  end

  # ------------------------------------------------------------------

  test "happy path: single attempt each, results merged, no compensation" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 0, 1), comp(:a))
      |> RetrySaga.step(:b, flaky_action(:b, 0, 2), comp(:b))

    assert {:ok, %{a: 1, b: 2}} = RetrySaga.execute(saga, %{})
    assert Recorder.events() == [{:action, :a}, {:action, :b}]
    assert Recorder.actions(:a) == 1
    assert Recorder.actions(:b) == 1
  end

  test "a step that fails twice then succeeds retries and completes" do
    # TODO
  end

  test "exhausting retries triggers compensation of earlier steps" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 0, 1), comp(:a, {:ok, :undo_a}))
      |> RetrySaga.step(:b, always_fail(:b, :nope), comp(:b), max_attempts: 2)
      |> RetrySaga.step(:c, flaky_action(:c, 0, 3), comp(:c))

    assert {:error, err} = RetrySaga.execute(saga, %{})

    assert err.step == :b
    assert err.error == :nope
    assert err.attempts == 2
    assert err.compensated == [:a]
    assert err.compensations == %{a: {:ok, :undo_a}}

    # b tried twice, c never ran, only a compensated.
    assert Recorder.actions(:a) == 1
    assert Recorder.actions(:b) == 2
    assert Recorder.actions(:c) == 0
    assert Recorder.events() |> Enum.filter(&match?({:comp, _}, &1)) == [{:comp, :a}]
  end

  test "default max_attempts is 1 (a single attempt, then failure)" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, always_fail(:a, :boom), comp(:a))

    assert {:error, err} = RetrySaga.execute(saga, %{})
    assert err.step == :a
    assert err.attempts == 1
    assert err.compensated == []
    assert err.compensations == %{}
    assert Recorder.actions(:a) == 1
  end

  test "retries reuse the same context; later steps see earlier results" do
    a = flaky_action(:a, 1, 10)
    b = fn ctx -> {:ok, ctx.a + 5} end

    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, a, comp(:a), max_attempts: 2)
      |> RetrySaga.step(:b, b, comp(:b))

    assert {:ok, %{a: 10, b: 15}} = RetrySaga.execute(saga, %{})
    assert Recorder.actions(:a) == 2
  end

  test "compensations run in reverse completion order" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 0, 1), comp(:a))
      |> RetrySaga.step(:b, flaky_action(:b, 0, 2), comp(:b))
      |> RetrySaga.step(:c, flaky_action(:c, 0, 3), comp(:c))
      |> RetrySaga.step(:d, always_fail(:d, :fail), comp(:d))

    assert {:error, err} = RetrySaga.execute(saga, %{})
    assert err.compensated == [:c, :b, :a]

    comps = Enum.filter(Recorder.events(), &match?({:comp, _}, &1))
    assert comps == [{:comp, :c}, {:comp, :b}, {:comp, :a}]
  end

  test "a failing compensation is recorded but the others still run" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 0, 1), comp(:a, {:ok, :undo_a}))
      |> RetrySaga.step(:b, flaky_action(:b, 0, 2), comp(:b, {:error, :undo_failed}))
      |> RetrySaga.step(:c, always_fail(:c, :nope), comp(:c))

    assert {:error, err} = RetrySaga.execute(saga, %{})
    assert err.compensated == [:b, :a]
    assert err.compensations == %{b: {:error, :undo_failed}, a: {:ok, :undo_a}}
  end

  test "a compensation sees its own step's stored result" do
    reserve = fn _ -> {:ok, %{reservation_id: "abc"}} end

    cancel = fn ctx ->
      Recorder.record({:comp_ctx, ctx[:reserve]})
      {:ok, :cancelled}
    end

    saga =
      RetrySaga.new()
      |> RetrySaga.step(:reserve, reserve, cancel)
      |> RetrySaga.step(:charge, always_fail(:charge, :declined), comp(:charge))

    assert {:error, _} = RetrySaga.execute(saga, %{})
    assert {:comp_ctx, %{reservation_id: "abc"}} in Recorder.events()
  end

  test "invalid max_attempts raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      RetrySaga.step(RetrySaga.new(), :a, fn _ -> {:ok, 1} end, fn _ -> :ok end, max_attempts: 0)
    end
  end

  test "empty saga returns the context unchanged" do
    assert {:ok, %{x: 1}} = RetrySaga.execute(RetrySaga.new(), %{x: 1})
    assert Recorder.events() == []
  end

  test "the reported error is the reason from the final attempt, not the first" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 0, 1), comp(:a))
      |> RetrySaga.step(:b, flaky_action(:b, 5, :never), comp(:b), max_attempts: 3)

    assert {:error, err} = RetrySaga.execute(saga, %{})
    assert err.step == :b
    # flaky_action reports {:attempt, n}; the last of 3 attempts is n == 3.
    assert err.error == {:attempt, 3}
    assert err.attempts == 3
    assert Recorder.actions(:b) == 3
  end

  test "the error map carries exactly the five documented keys" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 0, 1), comp(:a))
      |> RetrySaga.step(:b, always_fail(:b, :nope), comp(:b))

    assert {:error, err} = RetrySaga.execute(saga, %{})

    assert err |> Map.keys() |> Enum.sort() ==
             [:attempts, :compensated, :compensations, :error, :step]
  end

  test "an early step's compensation sees results stored by later completed steps" do
    seen = fn name ->
      fn ctx ->
        Recorder.record({:comp_saw, name, Map.take(ctx, [:a, :b, :c, :start])})
        {:ok, :undone}
      end
    end

    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 0, 1), seen.(:a))
      |> RetrySaga.step(:b, flaky_action(:b, 0, 2), seen.(:b))
      |> RetrySaga.step(:c, always_fail(:c, :boom), comp(:c))

    assert {:error, _err} = RetrySaga.execute(saga, %{start: :ctx})

    assert {:comp_saw, :a, %{a: 1, b: 2, start: :ctx}} in Recorder.events()
    assert {:comp_saw, :b, %{a: 1, b: 2, start: :ctx}} in Recorder.events()
  end

  test "the starting context is preserved alongside the merged step results" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:reserve, flaky_action(:reserve, 1, :r1), comp(:reserve), max_attempts: 2)
      |> RetrySaga.step(:charge, fn ctx -> {:ok, {ctx.order_id, ctx.reserve}} end, comp(:charge))

    assert {:ok, ctx} = RetrySaga.execute(saga, %{order_id: 42, extra: :kept})
    assert ctx == %{order_id: 42, extra: :kept, reserve: :r1, charge: {42, :r1}}
  end

  test "a non-integer max_attempts raises ArgumentError" do
    ok = fn _ -> {:ok, 1} end
    undo = fn _ -> {:ok, :undone} end

    for bad <- [:lots, 2.0, nil, -1, "3"] do
      assert_raise ArgumentError, fn ->
        RetrySaga.step(RetrySaga.new(), :a, ok, undo, max_attempts: bad)
      end
    end
  end

  test "no later action is interleaved between a step's retry attempts" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 2, :done), comp(:a), max_attempts: 3)
      |> RetrySaga.step(:b, flaky_action(:b, 1, :ok), comp(:b), max_attempts: 2)

    assert {:ok, _ctx} = RetrySaga.execute(saga, %{})

    assert Recorder.events() == [
             {:action, :a},
             {:action, :a},
             {:action, :a},
             {:action, :b},
             {:action, :b}
           ]
  end
end
```
