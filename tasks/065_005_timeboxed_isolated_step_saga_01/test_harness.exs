defmodule TimeboxedSagaTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  # --- Inline recorder to observe compensation ordering ---

  defmodule Recorder do
    use Agent

    def start_link(_ \\ nil), do: Agent.start_link(fn -> [] end, name: __MODULE__)
    def record(event), do: Agent.update(__MODULE__, &[event | &1])
    def events, do: Agent.get(__MODULE__, &Enum.reverse(&1))
  end

  setup do
    start_supervised!(Recorder)
    :ok
  end

  # --- Step-builder helpers ---

  defp ok_step(name, result, comp_ret \\ {:ok, :undone}, timeout \\ 1_000) do
    %{
      name: name,
      action: fn _ctx -> {:ok, result} end,
      compensation: fn _ctx ->
        Recorder.record({:comp, name})
        comp_ret
      end,
      timeout: timeout
    }
  end

  defp fail_step(name, reason) do
    %{
      name: name,
      action: fn _ctx -> {:error, reason} end,
      compensation: fn _ctx ->
        Recorder.record({:comp, name})
        {:ok, :undone}
      end,
      timeout: 1_000
    }
  end

  # -------------------------------------------------------
  # Happy path
  # -------------------------------------------------------

  test "runs all steps and merges results into the context" do
    steps = [
      ok_step(:reserve, %{id: "r1"}),
      ok_step(:charge, %{txn: "t1"}),
      ok_step(:ship, :shipped)
    ]

    assert {:ok, ctx} = TimeboxedSaga.run(steps, %{order_id: 42})
    assert ctx.order_id == 42
    assert ctx.reserve == %{id: "r1"}
    assert ctx.charge == %{txn: "t1"}
    assert ctx.ship == :shipped
    assert Recorder.events() == []
  end

  test "later steps see the results of earlier steps in the context" do
    steps = [
      %{name: :a, action: fn _ctx -> {:ok, 10} end, compensation: fn _ -> :ok end},
      %{name: :b, action: fn ctx -> {:ok, ctx.a + 5} end, compensation: fn _ -> :ok end}
    ]

    assert {:ok, %{a: 10, b: 15}} = TimeboxedSaga.run(steps, %{})
  end

  test "empty saga returns the context unchanged" do
    assert {:ok, %{x: 1}} = TimeboxedSaga.run([], %{x: 1})
    assert Recorder.events() == []
  end

  test "run/2 uses the default timeout of 5000ms for a fast step" do
    # No :timeout on the step and no :default_timeout opt -> the 5000ms default
    # applies; a fast action completes well within it.
    step = %{name: :quick, action: fn _ -> {:ok, :done} end, compensation: fn _ -> :ok end}
    assert {:ok, ctx} = TimeboxedSaga.run([step], %{})
    assert ctx.quick == :done
  end

  # -------------------------------------------------------
  # Failure & compensation semantics
  # -------------------------------------------------------

  test "middle step fails: earlier steps compensated, later step never runs" do
    ran = self()

    ship = %{
      name: :ship,
      action: fn _ -> send(ran, :ship_ran) && {:ok, :shipped} end,
      compensation: fn _ -> Recorder.record({:comp, :ship}) end
    }

    steps = [
      ok_step(:reserve, %{id: "r1"}, {:ok, :cancelled}),
      fail_step(:charge, :declined),
      ship
    ]

    assert {:error, err} = TimeboxedSaga.run(steps, %{})
    assert err.step == :charge
    assert err.error == :declined
    assert err.compensated == [:reserve]
    assert err.compensations == %{reserve: {:ok, :cancelled}}
    refute_received :ship_ran
    assert Recorder.events() == [{:comp, :reserve}]
  end

  test "first step failing runs no compensations" do
    steps = [fail_step(:reserve, :boom), ok_step(:charge, :ok)]

    assert {:error, err} = TimeboxedSaga.run(steps, %{})
    assert err.step == :reserve
    assert err.error == :boom
    assert err.compensated == []
    assert err.compensations == %{}
    assert Recorder.events() == []
  end

  test "compensations run in reverse completion order" do
    steps = [ok_step(:a, 1), ok_step(:b, 2), ok_step(:c, 3), fail_step(:d, :fail)]

    assert {:error, err} = TimeboxedSaga.run(steps, %{})
    assert err.step == :d
    assert err.compensated == [:c, :b, :a]
    assert Recorder.events() == [{:comp, :c}, {:comp, :b}, {:comp, :a}]
  end

  test "a compensation sees the accumulated context including its own result" do
    seen = self()

    reserve = %{
      name: :reserve,
      action: fn _ -> {:ok, %{reservation_id: "abc"}} end,
      compensation: fn ctx ->
        send(seen, {:comp_ctx, ctx[:reserve], Map.has_key?(ctx, :charge)})
        {:ok, :cancelled}
      end
    }

    steps = [reserve, fail_step(:charge, :declined)]
    assert {:error, _} = TimeboxedSaga.run(steps, %{seed: :s})
    assert_received {:comp_ctx, %{reservation_id: "abc"}, false}
  end

  test "best-effort: an erroring compensation does not stop the others" do
    steps = [
      ok_step(:a, 1, {:ok, :undo_a}),
      ok_step(:b, 2, {:error, :undo_failed}),
      fail_step(:c, :nope)
    ]

    assert {:error, err} = TimeboxedSaga.run(steps, %{})
    assert err.compensated == [:b, :a]
    assert err.compensations == %{b: {:error, :undo_failed}, a: {:ok, :undo_a}}
    assert Recorder.events() == [{:comp, :b}, {:comp, :a}]
  end

  test "error map has exactly the four documented keys" do
    steps = [ok_step(:a, 1), fail_step(:b, :nope)]
    assert {:error, err} = TimeboxedSaga.run(steps, %{})
    assert Enum.sort(Map.keys(err)) == [:compensated, :compensations, :error, :step]
  end

  # -------------------------------------------------------
  # Crash / bad-return handling
  # -------------------------------------------------------

  test "an action that raises fails with {:crashed, exception} and triggers compensation" do
    boom = %{name: :b, action: fn _ -> raise "kaboom" end, compensation: fn _ -> :ok end}
    steps = [ok_step(:a, 1, {:ok, :undo_a}), boom]

    assert {:error, err} = TimeboxedSaga.run(steps, %{})
    assert err.step == :b
    assert {:crashed, %RuntimeError{message: "kaboom"}} = err.error
    assert err.compensated == [:a]
    assert err.compensations == %{a: {:ok, :undo_a}}
  end

  test "an action returning a non-ok/non-error term fails with {:bad_return, value}" do
    weird = %{name: :b, action: fn _ -> :totally_wrong end, compensation: fn _ -> :ok end}
    steps = [ok_step(:a, 1), weird]

    assert {:error, err} = TimeboxedSaga.run(steps, %{})
    assert err.step == :b
    assert err.error == {:bad_return, :totally_wrong}
    assert err.compensated == [:a]
  end

  # -------------------------------------------------------
  # Compensation that raises is isolated
  # -------------------------------------------------------

  test "a raising compensation is recorded as {:raised, _} and remaining compensations still run" do
    raising = %{
      name: :b,
      action: fn _ -> {:ok, 2} end,
      compensation: fn _ ->
        Recorder.record({:comp, :b})
        raise "undo exploded"
      end
    }

    steps = [ok_step(:a, 1, {:ok, :undo_a}), raising, fail_step(:c, :stop)]

    assert {:error, err} = TimeboxedSaga.run(steps, %{})
    assert err.compensated == [:b, :a]
    assert {:raised, %RuntimeError{message: "undo exploded"}} = err.compensations[:b]
    assert err.compensations[:a] == {:ok, :undo_a}
    # :a still ran even though :b's compensation blew up.
    assert Recorder.events() == [{:comp, :b}, {:comp, :a}]
  end

  # -------------------------------------------------------
  # Timeout: kill process, discard stale result
  # -------------------------------------------------------

  test "a timed-out action is killed, its late side effects never happen, and the step fails with :timeout" do
    test_pid = self()

    slow = %{
      name: :b,
      action: fn _ ->
        Process.sleep(300)
        send(test_pid, :late)
        {:ok, :done}
      end,
      compensation: fn _ -> Recorder.record({:comp, :b}) end,
      timeout: 50
    }

    steps = [ok_step(:a, 1, {:ok, :undo_a}), slow]

    assert {:error, err} = TimeboxedSaga.run(steps, %{})
    assert err.step == :b
    assert err.error == :timeout
    assert err.compensated == [:a]
    assert err.compensations == %{a: {:ok, :undo_a}}
    # The killed action never reached its send/2.
    refute_receive :late, 400
    # The failed (timed-out) step is not compensated.
    assert Recorder.events() == [{:comp, :a}]
  end

  test "default_timeout opt applies to steps without their own :timeout" do
    slow = %{
      name: :b,
      action: fn _ -> Process.sleep(300) end,
      compensation: fn _ -> :ok end
    }

    assert {:error, err} = TimeboxedSaga.run([slow], %{}, default_timeout: 50)
    assert err.step == :b
    assert err.error == :timeout
  end

  test "a per-step :timeout overrides a larger default_timeout (step times out)" do
    slow = %{
      name: :b,
      action: fn _ -> Process.sleep(300) end,
      compensation: fn _ -> :ok end,
      timeout: 50
    }

    assert {:error, err} = TimeboxedSaga.run([slow], %{}, default_timeout: 5_000)
    assert err.error == :timeout
  end

  test "a per-step :timeout overrides a smaller default_timeout (step succeeds)" do
    step = %{
      name: :b,
      action: fn _ ->
        Process.sleep(150)
        {:ok, :done}
      end,
      compensation: fn _ -> :ok end,
      timeout: 500
    }

    assert {:ok, ctx} = TimeboxedSaga.run([step], %{}, default_timeout: 50)
    assert ctx.b == :done
  end

  # -------------------------------------------------------
  # Property: all-success merges every result
  # -------------------------------------------------------

  property "an all-success saga merges every step's result into the context" do
    check all(n <- integer(1..8)) do
      steps =
        for i <- 1..n do
          %{
            name: {:s, i},
            action: fn _ -> {:ok, i} end,
            compensation: fn _ -> :ok end,
            timeout: 1_000
          }
        end

      assert {:ok, ctx} = TimeboxedSaga.run(steps, %{seed: 7})
      assert ctx.seed == 7
      for i <- 1..n, do: assert(ctx[{:s, i}] == i)
    end
  end

  test "the forward action runs in a process other than the caller" do
    step = %{
      name: :where,
      action: fn _ -> {:ok, self()} end,
      compensation: fn _ -> :ok end
    }

    assert {:ok, ctx} = TimeboxedSaga.run([step], %{})
    assert is_pid(ctx.where)
    # Inline execution would make the action's self() equal the caller's pid.
    assert ctx.where != self()
  end

  test "an action that exits fails with {:crashed, exit_reason} and triggers compensation" do
    bad = %{name: :b, action: fn _ -> exit(:boom) end, compensation: fn _ -> :ok end}
    steps = [ok_step(:a, 1, {:ok, :undo_a}), bad]

    assert {:error, err} = TimeboxedSaga.run(steps, %{})
    assert err.step == :b
    assert err.error == {:crashed, :boom}
    assert err.compensated == [:a]
    assert err.compensations == %{a: {:ok, :undo_a}}
  end
end
