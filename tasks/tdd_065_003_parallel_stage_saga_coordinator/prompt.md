# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    spy = fn ctx ->
      Recorder.record({:comp_ctx, Map.take(ctx, [:a, :b, :c])})
      {:ok, :undone}
    end

    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([{:a, ok_action(:a, 1), spy}])
      |> ParallelSaga.stage([
        {:b, ok_action(:b, 2), comp(:b)},
        {:c, fail_action(:c, :boom), comp(:c)}
      ])

    assert {:error, _err} = ParallelSaga.execute(saga, %{})
    assert {:comp_ctx, %{a: 1, b: 2}} in Recorder.events()
  end

  test "a compensation that is not arity-1 raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      ParallelSaga.stage(ParallelSaga.new(), [{:a, fn _ -> :ok end, fn -> :ok end}])
    end
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
