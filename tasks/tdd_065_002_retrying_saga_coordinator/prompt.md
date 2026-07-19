# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 2, :done), comp(:a), max_attempts: 3)
      |> RetrySaga.step(:b, flaky_action(:b, 0, :ok), comp(:b))

    assert {:ok, ctx} = RetrySaga.execute(saga, %{})
    assert ctx.a == :done
    assert ctx.b == :ok
    assert Recorder.actions(:a) == 3
    # No compensations ran.
    refute Enum.any?(Recorder.events(), &match?({:comp, _}, &1))
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

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
