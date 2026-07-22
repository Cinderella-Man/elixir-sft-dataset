# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule ParallelSaga do
  @moduledoc """
  A staged saga / compensating-transaction coordinator.

  The saga is a list of stages; the steps within a stage run **concurrently**, each
  receiving the same start-of-stage context. If any step in a stage fails, the
  succeeded steps of that stage plus all earlier stages are compensated (best-effort)
  in reverse of their declared order, stage by stage.
  """

  @opaque t :: %__MODULE__{stages: [[step()]]}
  @type context :: map()
  @type step :: %{
          name: term(),
          action: (context() -> {:ok, term()} | {:error, term()}),
          compensation: (context() -> term())
        }
  @type error :: %{
          stage: non_neg_integer(),
          failed: %{optional(term()) => term()},
          compensated: [term()],
          compensations: %{optional(term()) => term()}
        }

  @await_timeout 5_000

  defstruct stages: []

  @doc "Returns a new, empty saga."
  @spec new() :: t()
  def new, do: %__MODULE__{stages: []}

  @doc "Appends a stage of `{name, action, compensation}` tuples."
  @spec stage(t(), [{term(), function(), function()}]) :: t()
  def stage(%__MODULE__{stages: stages} = saga, steps) when is_list(steps) do
    normalized =
      Enum.map(steps, fn {name, action, compensation} ->
        unless is_function(action, 1) and is_function(compensation, 1) do
          raise ArgumentError, "action and compensation must be arity-1 functions"
        end

        %{name: name, action: action, compensation: compensation}
      end)

    %__MODULE__{saga | stages: stages ++ [normalized]}
  end

  @doc "Runs the saga from `context`."
  @spec execute(t(), context()) :: {:ok, context()} | {:error, error()}
  def execute(%__MODULE__{stages: stages}, context) when is_map(context) do
    run_stages(stages, 0, context, [])
  end

  # `completed` holds step maps in reverse completion order (most recent first).
  defp run_stages([], _idx, context, _completed), do: {:ok, context}

  defp run_stages([stage | rest], idx, context, completed) do
    results =
      stage
      |> Enum.map(fn step -> {step, Task.async(fn -> step.action.(context) end)} end)
      |> Enum.map(fn {step, task} -> {step, Task.await(task, @await_timeout)} end)

    failures = for {step, {:error, reason}} <- results, into: %{}, do: {step.name, reason}

    if map_size(failures) == 0 do
      new_context =
        Enum.reduce(results, context, fn {step, {:ok, result}}, acc ->
          Map.put(acc, step.name, result)
        end)

      succeeded = Enum.map(results, fn {step, _} -> step end)
      run_stages(rest, idx + 1, new_context, Enum.reverse(succeeded) ++ completed)
    else
      succeeded = for {step, {:ok, _}} <- results, do: step

      comp_context =
        Enum.reduce(results, context, fn
          {step, {:ok, result}}, acc -> Map.put(acc, step.name, result)
          {_step, {:error, _}}, acc -> acc
        end)

      to_compensate = Enum.reverse(succeeded) ++ completed
      compensate(to_compensate, comp_context, idx, failures)
    end
  end

  defp compensate(to_compensate, context, stage_idx, failures) do
    {compensated, compensations} =
      Enum.reduce(to_compensate, {[], %{}}, fn
        %{name: name, compensation: comp}, {names, results} ->
          result = comp.(context)
          {[name | names], Map.put(results, name, result)}
      end)

    {:error,
     %{
       stage: stage_idx,
       failed: failures,
       compensated: Enum.reverse(compensated),
       compensations: compensations
     }}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule ParallelSagaTest do
  use ExUnit.Case, async: false

  defmodule Recorder do
    use Agent

    def start_link(_ \\ nil), do: Agent.start_link(fn -> [] end, name: __MODULE__)
    def record(event), do: Agent.update(__MODULE__, &[event | &1])
    def events, do: Agent.get(__MODULE__, &Enum.reverse(&1))
    def comps, do: Enum.filter(events(), &match?({:comp, _}, &1))

    def action_names,
      do: for({:action, n} <- events(), into: MapSet.new(), do: n)
  end

  setup do
    start_supervised!(Recorder)
    :ok
  end

  defp ok_action(name, result) do
    fn _ctx ->
      Recorder.record({:action, name})
      {:ok, result}
    end
  end

  defp fail_action(name, reason) do
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

  test "happy path: all stages succeed and results merge" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([
        {:a, ok_action(:a, 1), comp(:a)},
        {:b, ok_action(:b, 2), comp(:b)}
      ])
      |> ParallelSaga.stage([{:c, ok_action(:c, 3), comp(:c)}])

    assert {:ok, ctx} = ParallelSaga.execute(saga, %{order_id: 7})
    assert ctx.order_id == 7
    assert ctx.a == 1 and ctx.b == 2 and ctx.c == 3

    assert Recorder.action_names() == MapSet.new([:a, :b, :c])
    assert Recorder.comps() == []
  end

  test "steps in the same stage do not see each other's results" do
    a = fn ctx -> {:ok, Map.has_key?(ctx, :b)} end
    b = fn ctx -> {:ok, Map.has_key?(ctx, :a)} end

    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([{:a, a, comp(:a)}, {:b, b, comp(:b)}])

    assert {:ok, ctx} = ParallelSaga.execute(saga, %{})
    assert ctx.a == false
    assert ctx.b == false
  end

  test "a later stage sees an earlier stage's results" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([{:a, ok_action(:a, 10), comp(:a)}])
      |> ParallelSaga.stage([{:b, fn ctx -> {:ok, ctx.a + 5} end, comp(:b)}])

    assert {:ok, %{a: 10, b: 15}} = ParallelSaga.execute(saga, %{})
  end

  test "a failing step compensates its succeeded sibling and earlier stages" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([
        {:a, ok_action(:a, 1), comp(:a)},
        {:b, ok_action(:b, 2), comp(:b)}
      ])
      |> ParallelSaga.stage([
        {:c, fail_action(:c, :boom), comp(:c)},
        {:d, ok_action(:d, 4), comp(:d)}
      ])

    assert {:error, err} = ParallelSaga.execute(saga, %{})

    assert err.stage == 1
    assert err.failed == %{c: :boom}
    # succeeded sibling first, then earlier stage in reverse declared order.
    assert err.compensated == [:d, :b, :a]
    assert Map.keys(err.compensations) |> Enum.sort() == [:a, :b, :d]
    # the failed step is never compensated.
    refute {:comp, :c} in Recorder.events()
    assert Recorder.comps() == [{:comp, :d}, {:comp, :b}, {:comp, :a}]
  end

  test "multiple failures in a stage are all reported" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([
        {:a, fail_action(:a, :e1), comp(:a)},
        {:b, fail_action(:b, :e2), comp(:b)},
        {:c, ok_action(:c, 3), comp(:c)}
      ])

    assert {:error, err} = ParallelSaga.execute(saga, %{})
    assert err.stage == 0
    assert err.failed == %{a: :e1, b: :e2}
    # only the succeeded step is compensated; no earlier stages exist.
    assert err.compensated == [:c]
  end

  test "within-stage compensation runs in reverse declared order" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([
        {:c, ok_action(:c, 1), comp(:c)},
        {:d, ok_action(:d, 2), comp(:d)},
        {:e, fail_action(:e, :fail), comp(:e)}
      ])

    assert {:error, err} = ParallelSaga.execute(saga, %{})
    assert err.compensated == [:d, :c]
    assert Recorder.comps() == [{:comp, :d}, {:comp, :c}]
  end

  test "best-effort compensation: an erroring compensation does not stop the rest" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([{:a, ok_action(:a, 1), comp(:a, {:ok, :undo_a})}])
      |> ParallelSaga.stage([
        {:b, ok_action(:b, 2), comp(:b, {:error, :undo_failed})},
        {:c, fail_action(:c, :nope), comp(:c)}
      ])

    assert {:error, err} = ParallelSaga.execute(saga, %{})
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
      ParallelSaga.new()
      |> ParallelSaga.stage([{:reserve, reserve, cancel}])
      |> ParallelSaga.stage([{:charge, fail_action(:charge, :declined), comp(:charge)}])

    assert {:error, _} = ParallelSaga.execute(saga, %{})
    assert {:comp_ctx, %{reservation_id: "abc"}} in Recorder.events()
  end

  test "bad step tuple raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      ParallelSaga.stage(ParallelSaga.new(), [{:a, fn -> :ok end, fn _ -> :ok end}])
    end
  end

  test "empty saga returns the context unchanged" do
    assert {:ok, %{x: 1}} = ParallelSaga.execute(ParallelSaga.new(), %{x: 1})
    assert Recorder.events() == []
  end

  test "steps within a stage are started before any of them completes" do
    parent = self()

    rendezvous = fn name ->
      fn _ctx ->
        send(parent, {:started, name, self()})

        receive do
          :go -> {:ok, name}
        after
          2_000 -> {:error, :never_released}
        end
      end
    end

    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([
        {:a, rendezvous.(:a), comp(:a)},
        {:b, rendezvous.(:b), comp(:b)}
      ])

    runner = Task.async(fn -> ParallelSaga.execute(saga, %{}) end)

    assert_receive {:started, :a, pid_a}, 1_000
    assert_receive {:started, :b, pid_b}, 1_000

    send(pid_a, :go)
    send(pid_b, :go)

    assert {:ok, %{a: :a, b: :b}} = Task.await(runner, 5_000)
  end

  test "a failing stage aborts the saga so later stages never run" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([{:a, fail_action(:a, :boom), comp(:a)}])
      |> ParallelSaga.stage([{:b, ok_action(:b, 2), comp(:b)}])

    assert {:error, err} = ParallelSaga.execute(saga, %{})
    assert err.stage == 0
    assert err.failed == %{a: :boom}
    assert Recorder.action_names() == MapSet.new([:a])
    assert Recorder.comps() == []
  end

  test "the error map carries exactly the four documented keys" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([
        {:a, ok_action(:a, 1), comp(:a)},
        {:b, fail_action(:b, :boom), comp(:b)}
      ])

    assert {:error, err} = ParallelSaga.execute(saga, %{})

    assert err |> Map.keys() |> Enum.sort() ==
             [:compensated, :compensations, :failed, :stage]
  end

  test "compensation walks every earlier stage most recent stage first" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([
        {:a, ok_action(:a, 1), comp(:a)},
        {:b, ok_action(:b, 2), comp(:b)}
      ])
      |> ParallelSaga.stage([
        {:c, ok_action(:c, 3), comp(:c)},
        {:d, ok_action(:d, 4), comp(:d)}
      ])
      |> ParallelSaga.stage([
        {:e, ok_action(:e, 5), comp(:e)},
        {:f, fail_action(:f, :nope), comp(:f)}
      ])

    assert {:error, err} = ParallelSaga.execute(saga, %{})
    assert err.stage == 2
    assert err.compensated == [:e, :d, :c, :b, :a]

    assert Recorder.comps() ==
             [{:comp, :e}, {:comp, :d}, {:comp, :c}, {:comp, :b}, {:comp, :a}]
  end

  test "an earlier compensation sees the failing stage's succeeded results" do
    # TODO
  end

  test "a compensation that is not arity-1 raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      ParallelSaga.stage(ParallelSaga.new(), [{:a, fn _ -> :ok end, fn -> :ok end}])
    end
  end
end
```
