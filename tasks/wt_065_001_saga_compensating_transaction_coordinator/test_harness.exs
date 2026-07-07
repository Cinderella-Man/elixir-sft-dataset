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
end
