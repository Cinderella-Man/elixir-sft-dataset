# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule SagaTest do
  use ExUnit.Case, async: false

  # --- Inline recorder to observe action/compensation ordering ---

  defmodule Recorder do
    use Agent

    def start_link(_ \\ nil) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def record(event), do: Agent.update(__MODULE__, &[event | &1])
    def events, do: Agent.get(__MODULE__, &Enum.reverse(&1))
  end

  setup do
    start_supervised!(Recorder)
    :ok
  end

  # --- Helpers that build actions / compensations ---

  defp ok_action(name, result) do
    fn ctx ->
      Recorder.record({:action, name})
      _ = ctx
      {:ok, result}
    end
  end

  defp fail_action(name, reason) do
    fn ctx ->
      Recorder.record({:action, name})
      _ = ctx
      {:error, reason}
    end
  end

  defp comp(name, ret \\ {:ok, :compensated}) do
    fn ctx ->
      Recorder.record({:comp, name})
      _ = ctx
      ret
    end
  end

  # -------------------------------------------------------
  # Happy path
  # -------------------------------------------------------

  test "runs all steps and merges results into the context" do
    saga =
      Saga.new()
      |> Saga.step(:reserve, ok_action(:reserve, %{id: "r1"}), comp(:reserve))
      |> Saga.step(:charge, ok_action(:charge, %{txn: "t1"}), comp(:charge))
      |> Saga.step(:ship, ok_action(:ship, :shipped), comp(:ship))

    assert {:ok, ctx} = Saga.execute(saga, %{order_id: 42})

    assert ctx.order_id == 42
    assert ctx.reserve == %{id: "r1"}
    assert ctx.charge == %{txn: "t1"}
    assert ctx.ship == :shipped

    # No compensations should have run
    assert Recorder.events() == [
             {:action, :reserve},
             {:action, :charge},
             {:action, :ship}
           ]
  end

  test "later steps see the results of earlier steps in the context" do
    saga =
      Saga.new()
      |> Saga.step(:a, fn _ctx -> {:ok, 10} end, comp(:a))
      |> Saga.step(:b, fn ctx -> {:ok, ctx.a + 5} end, comp(:b))

    assert {:ok, %{a: 10, b: 15}} = Saga.execute(saga, %{})
  end

  # -------------------------------------------------------
  # Failure: step 2 of 3 fails
  # -------------------------------------------------------

  test "step 2 of 3 fails: step 1 is compensated, step 3 never runs" do
    saga =
      Saga.new()
      |> Saga.step(:reserve, ok_action(:reserve, %{id: "r1"}), comp(:reserve, {:ok, :cancelled}))
      |> Saga.step(:charge, fail_action(:charge, :card_declined), comp(:charge))
      |> Saga.step(:ship, ok_action(:ship, :shipped), comp(:ship))

    assert {:error, err} = Saga.execute(saga, %{user_id: 1})

    assert err.step == :charge
    assert err.error == :card_declined
    assert err.compensated == [:reserve]
    assert err.compensations == %{reserve: {:ok, :cancelled}}

    # reserve action ran, charge action ran (and failed), ship never ran,
    # only reserve was compensated, charge was NOT compensated.
    events = Recorder.events()

    assert events == [
             {:action, :reserve},
             {:action, :charge},
             {:comp, :reserve}
           ]
  end

  # -------------------------------------------------------
  # Failure at the very first step
  # -------------------------------------------------------

  test "first step failing runs no compensations" do
    saga =
      Saga.new()
      |> Saga.step(:reserve, fail_action(:reserve, :boom), comp(:reserve))
      |> Saga.step(:charge, ok_action(:charge, :ok), comp(:charge))

    assert {:error, err} = Saga.execute(saga, %{})

    assert err.step == :reserve
    assert err.error == :boom
    assert err.compensated == []
    assert err.compensations == %{}

    assert Recorder.events() == [{:action, :reserve}]
  end

  # -------------------------------------------------------
  # Compensation order is reverse of completion
  # -------------------------------------------------------

  test "compensations run in reverse completion order" do
    saga =
      Saga.new()
      |> Saga.step(:a, ok_action(:a, 1), comp(:a))
      |> Saga.step(:b, ok_action(:b, 2), comp(:b))
      |> Saga.step(:c, ok_action(:c, 3), comp(:c))
      |> Saga.step(:d, fail_action(:d, :fail), comp(:d))

    assert {:error, err} = Saga.execute(saga, %{})

    assert err.step == :d
    assert err.compensated == [:c, :b, :a]

    assert Recorder.events() == [
             {:action, :a},
             {:action, :b},
             {:action, :c},
             {:action, :d},
             {:comp, :c},
             {:comp, :b},
             {:comp, :a}
           ]
  end

  # -------------------------------------------------------
  # Compensation receives the accumulated context
  # -------------------------------------------------------

  test "a compensation sees its own step's stored result in the context" do
    reserve = fn _ctx -> {:ok, %{reservation_id: "abc"}} end

    cancel = fn ctx ->
      Recorder.record({:comp_ctx, ctx[:reserve]})
      {:ok, :cancelled}
    end

    saga =
      Saga.new()
      |> Saga.step(:reserve, reserve, cancel)
      |> Saga.step(:charge, fail_action(:charge, :declined), comp(:charge))

    assert {:error, _} = Saga.execute(saga, %{})

    assert {:comp_ctx, %{reservation_id: "abc"}} in Recorder.events()
  end

  # -------------------------------------------------------
  # Best-effort compensation: an erroring compensation
  # does not stop the others
  # -------------------------------------------------------

  test "a failing compensation is recorded but remaining compensations still run" do
    saga =
      Saga.new()
      |> Saga.step(:a, ok_action(:a, 1), comp(:a, {:ok, :undo_a}))
      |> Saga.step(:b, ok_action(:b, 2), comp(:b, {:error, :undo_failed}))
      |> Saga.step(:c, fail_action(:c, :nope), comp(:c))

    assert {:error, err} = Saga.execute(saga, %{})

    assert err.step == :c
    assert err.error == :nope
    assert err.compensated == [:b, :a]
    assert err.compensations == %{b: {:error, :undo_failed}, a: {:ok, :undo_a}}

    # Even though :b's compensation errored, :a's still ran.
    assert Recorder.events() == [
             {:action, :a},
             {:action, :b},
             {:action, :c},
             {:comp, :b},
             {:comp, :a}
           ]
  end

  # -------------------------------------------------------
  # Empty saga
  # -------------------------------------------------------

  test "empty saga returns the context unchanged" do
    assert {:ok, %{x: 1}} = Saga.execute(Saga.new(), %{x: 1})
    assert Recorder.events() == []
  end

  # -------------------------------------------------------
  # A single successful step
  # -------------------------------------------------------

  test "single successful step" do
    saga = Saga.new() |> Saga.step(:only, ok_action(:only, :done), comp(:only))

    assert {:ok, ctx} = Saga.execute(saga, %{})
    assert ctx.only == :done
    assert Recorder.events() == [{:action, :only}]
  end

  test "error map contains exactly the four documented keys and nothing else" do
    saga =
      Saga.new()
      |> Saga.step(:a, ok_action(:a, 1), comp(:a))
      |> Saga.step(:b, fail_action(:b, :nope), comp(:b))

    assert {:error, err} = Saga.execute(saga, %{})

    assert Enum.sort(Map.keys(err)) == [:compensated, :compensations, :error, :step]
  end

  test "an earlier step's compensation sees later results but not the failing step's key" do
    record_ctx = fn name ->
      fn ctx ->
        Recorder.record({:comp_ctx, name, ctx})
        {:ok, :undone}
      end
    end

    saga =
      Saga.new()
      |> Saga.step(:a, ok_action(:a, 1), record_ctx.(:a))
      |> Saga.step(:b, ok_action(:b, 2), record_ctx.(:b))
      |> Saga.step(:c, fail_action(:c, :boom), comp(:c))

    assert {:error, _} = Saga.execute(saga, %{seed: :s})

    events = Recorder.events()
    assert {:comp_ctx, :a, ctx_a} = Enum.find(events, &match?({:comp_ctx, :a, _}, &1))

    assert ctx_a == %{seed: :s, a: 1, b: 2}
    refute Map.has_key?(ctx_a, :c)
  end

  test "a compensation returning an arbitrary term is recorded verbatim" do
    saga =
      Saga.new()
      |> Saga.step(:a, ok_action(:a, 1), comp(:a, :just_a_bare_atom))
      |> Saga.step(:b, ok_action(:b, 2), comp(:b, %{weird: [1, 2, 3]}))
      |> Saga.step(:c, fail_action(:c, :stop), comp(:c))

    assert {:error, err} = Saga.execute(saga, %{})

    assert err.compensated == [:b, :a]
    assert err.compensations == %{a: :just_a_bare_atom, b: %{weird: [1, 2, 3]}}
  end

  test "a step result overwrites a pre-existing context key of the same name" do
    saga =
      Saga.new()
      |> Saga.step(:order_id, ok_action(:order_id, 99), comp(:order_id))
      |> Saga.step(:next, fn ctx -> {:ok, ctx.order_id} end, comp(:next))

    assert {:ok, ctx} = Saga.execute(saga, %{order_id: 42})

    assert ctx.order_id == 99
    assert ctx.next == 99
  end

  test "non-atom step names work as context keys and in the error map" do
    saga =
      Saga.new()
      |> Saga.step("reserve", ok_action(:reserve, :held), comp(:reserve, {:ok, :released}))
      |> Saga.step({:charge, 1}, fail_action(:charge, :declined), comp(:charge))

    assert {:error, err} = Saga.execute(saga, %{})

    assert err.step == {:charge, 1}
    assert err.error == :declined
    assert err.compensated == ["reserve"]
    assert err.compensations == %{"reserve" => {:ok, :released}}
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
