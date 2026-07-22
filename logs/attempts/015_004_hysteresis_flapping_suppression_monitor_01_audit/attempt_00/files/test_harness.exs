defmodule StabilityMonitorTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!({StabilityMonitor, []})
    :ok
  end

  defp flush_probes do
    receive do
      {:probe, _} -> flush_probes()
    after
      0 -> :ok
    end
  end

  defp collect_probes(acc) do
    receive do
      {:probe, x} -> collect_probes([x | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "a freshly started monitor tracks nothing" do
    assert StabilityMonitor.states() == %{}
  end

  test "watch returns :ok and the service starts :up" do
    assert :ok = StabilityMonitor.watch("svc", fn -> :ok end, 10_000)
    assert StabilityMonitor.state("svc") == :up
    assert StabilityMonitor.states() == %{"svc" => :up}
  end

  test "watch guards a non-positive interval" do
    assert_raise FunctionClauseError, fn ->
      StabilityMonitor.watch("bad", fn -> :ok end, 0)
    end

    assert :ok = StabilityMonitor.watch("ok", fn -> :ok end, 10_000)
    assert StabilityMonitor.state("ok") == :up
  end

  test "watch guards a non-zero-arity check function" do
    assert_raise FunctionClauseError, fn ->
      StabilityMonitor.watch("bad", fn _x -> :ok end, 10_000)
    end

    assert :ok = StabilityMonitor.watch("ok", fn -> :ok end, 10_000)
    assert StabilityMonitor.state("ok") == :up
  end

  test "state and force_check report unknown services" do
    assert StabilityMonitor.state("nope") == {:error, :not_found}
    assert StabilityMonitor.force_check("nope") == {:error, :not_found}
  end

  test "a service goes :down only after fail_confirm consecutive failures" do
    test = self()
    hook = fn n, f, t -> send(test, {:trans, n, f, t}) end

    :ok =
      StabilityMonitor.watch("svc", fn -> {:error, :x} end, 10_000,
        fail_confirm: 3,
        ok_confirm: 2,
        on_transition: hook
      )

    assert {:ok, :up} = StabilityMonitor.force_check("svc")
    assert {:ok, :up} = StabilityMonitor.force_check("svc")
    refute_receive {:trans, "svc", _, _}, 50

    assert {:ok, :down} = StabilityMonitor.force_check("svc")
    assert_receive {:trans, "svc", :up, :down}, 500
    assert StabilityMonitor.state("svc") == :down

    # Already down: further failures do not re-fire.
    assert {:ok, :down} = StabilityMonitor.force_check("svc")
    refute_receive {:trans, "svc", _, _}, 50
  end

  test "the default confirmations are fail_confirm 3 and ok_confirm 2" do
    {:ok, box} = Agent.start_link(fn -> {:error, :e} end)
    check = fn -> Agent.get(box, & &1) end
    :ok = StabilityMonitor.watch("svc", check, 10_000)

    assert {:ok, :up} = StabilityMonitor.force_check("svc")
    assert {:ok, :up} = StabilityMonitor.force_check("svc")
    assert {:ok, :down} = StabilityMonitor.force_check("svc")

    Agent.update(box, fn _ -> :ok end)
    assert {:ok, :down} = StabilityMonitor.force_check("svc")
    assert {:ok, :up} = StabilityMonitor.force_check("svc")
  end

  test "recovery requires ok_confirm consecutive successes" do
    test = self()
    hook = fn n, f, t -> send(test, {:trans, n, f, t}) end
    {:ok, box} = Agent.start_link(fn -> {:error, :e} end)
    check = fn -> Agent.get(box, & &1) end

    :ok =
      StabilityMonitor.watch("svc", check, 10_000,
        fail_confirm: 1,
        ok_confirm: 2,
        on_transition: hook
      )

    assert {:ok, :down} = StabilityMonitor.force_check("svc")
    assert_receive {:trans, "svc", :up, :down}, 500

    Agent.update(box, fn _ -> :ok end)
    assert {:ok, :down} = StabilityMonitor.force_check("svc")
    refute_receive {:trans, "svc", _, _}, 50

    assert {:ok, :up} = StabilityMonitor.force_check("svc")
    assert_receive {:trans, "svc", :down, :up}, 500
  end

  test "alternating results are suppressed and never confirm a transition" do
    test = self()
    hook = fn n, f, t -> send(test, {:trans, n, f, t}) end
    {:ok, box} = Agent.start_link(fn -> {:error, :e} end)
    check = fn -> Agent.get(box, & &1) end

    :ok =
      StabilityMonitor.watch("svc", check, 10_000,
        fail_confirm: 2,
        ok_confirm: 2,
        on_transition: hook
      )

    assert {:ok, :up} = StabilityMonitor.force_check("svc")
    Agent.update(box, fn _ -> :ok end)
    assert {:ok, :up} = StabilityMonitor.force_check("svc")
    Agent.update(box, fn _ -> {:error, :e} end)
    assert {:ok, :up} = StabilityMonitor.force_check("svc")
    Agent.update(box, fn _ -> :ok end)
    assert {:ok, :up} = StabilityMonitor.force_check("svc")

    assert StabilityMonitor.state("svc") == :up
    refute_receive {:trans, "svc", _, _}, 50
  end

  test "re-watching resets the confirmed state and applies the new config" do
    :ok = StabilityMonitor.watch("svc", fn -> {:error, :x} end, 10_000, fail_confirm: 1)
    assert {:ok, :down} = StabilityMonitor.force_check("svc")
    assert StabilityMonitor.state("svc") == :down

    :ok = StabilityMonitor.watch("svc", fn -> {:error, :y} end, 10_000, fail_confirm: 2)
    assert StabilityMonitor.state("svc") == :up

    # New fail_confirm of 2 governs now: one failure stays :up.
    assert {:ok, :up} = StabilityMonitor.force_check("svc")
    assert {:ok, :down} = StabilityMonitor.force_check("svc")
  end

  test "re-watching kills the previous schedule" do
    test = self()

    a = fn ->
      send(test, {:probe, :a})
      :ok
    end

    :ok = StabilityMonitor.watch("svc", a, 20)
    assert_receive {:probe, :a}, 1_000
    assert_receive {:probe, :a}, 1_000

    b = fn ->
      send(test, {:probe, :b})
      :ok
    end

    :ok = StabilityMonitor.watch("svc", b, 20)

    flush_probes()
    Process.sleep(200)
    ticks = collect_probes([])

    assert :b in ticks
    refute :a in ticks
  end

  test "unwatch removes a service and kills its schedule" do
    test = self()

    c = fn ->
      send(test, {:probe, :c})
      :ok
    end

    :ok = StabilityMonitor.watch("svc", c, 20)
    assert_receive {:probe, :c}, 1_000

    assert :ok = StabilityMonitor.unwatch("svc")
    assert StabilityMonitor.state("svc") == {:error, :not_found}
    assert StabilityMonitor.unwatch("svc") == {:error, :not_found}

    flush_probes()
    Process.sleep(200)
    assert collect_probes([]) == []
  end

  test "periodic checks run at the configured interval" do
    test = self()

    :ok =
      StabilityMonitor.watch(
        "svc",
        fn ->
          send(test, {:probe, :a})
          :ok
        end,
        20
      )

    assert_receive {:probe, :a}, 1_000
    assert_receive {:probe, :a}, 1_000
  end

  test "services are independent" do
    :ok = StabilityMonitor.watch("a", fn -> {:error, :x} end, 10_000, fail_confirm: 1)
    :ok = StabilityMonitor.watch("b", fn -> :ok end, 10_000)

    assert {:ok, :down} = StabilityMonitor.force_check("a")
    assert {:ok, :up} = StabilityMonitor.force_check("b")
    assert StabilityMonitor.states() == %{"a" => :down, "b" => :up}
  end

  test "unexpected messages do not crash the server" do
    :ok = StabilityMonitor.watch("svc", fn -> :ok end, 10_000)
    send(StabilityMonitor, :garbage)
    send(StabilityMonitor, {:more, :garbage})
    assert StabilityMonitor.state("svc") == :up
  end

  test "atom and tuple service names work and compare by value" do
    :ok = StabilityMonitor.watch(:svc, fn -> :ok end, 10_000)
    :ok = StabilityMonitor.watch({:svc, 1}, fn -> {:error, :x} end, 10_000, fail_confirm: 1)

    assert StabilityMonitor.state(:svc) == :up
    assert {:ok, :down} = StabilityMonitor.force_check({:svc, 1})
    assert StabilityMonitor.states() == %{:svc => :up, {:svc, 1} => :down}
  end

  test "a down-up-down cycle fires on_transition once per confirmed change" do
    test = self()
    hook = fn n, f, t -> send(test, {:trans, n, f, t}) end
    {:ok, box} = Agent.start_link(fn -> {:error, :e} end)
    check = fn -> Agent.get(box, & &1) end

    :ok =
      StabilityMonitor.watch("svc", check, 10_000,
        fail_confirm: 1,
        ok_confirm: 1,
        on_transition: hook
      )

    assert {:ok, :down} = StabilityMonitor.force_check("svc")
    assert_receive {:trans, "svc", :up, :down}, 500

    Agent.update(box, fn _ -> :ok end)
    assert {:ok, :up} = StabilityMonitor.force_check("svc")
    assert_receive {:trans, "svc", :down, :up}, 500

    Agent.update(box, fn _ -> {:error, :e} end)
    assert {:ok, :down} = StabilityMonitor.force_check("svc")
    assert_receive {:trans, "svc", :up, :down}, 500

    refute_receive {:trans, "svc", _, _}, 50
  end

  test "force_check calls the check function exactly once" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    check = fn ->
      Agent.update(counter, &(&1 + 1))
      :ok
    end

    :ok = StabilityMonitor.watch("svc", check, 10_000)
    assert {:ok, :up} = StabilityMonitor.force_check("svc")
    assert Agent.get(counter, & &1) == 1
  end

  test "watch guards a non-integer interval" do
    assert_raise FunctionClauseError, fn ->
      StabilityMonitor.watch("bad", fn -> :ok end, 10.0)
    end

    assert :ok = StabilityMonitor.watch("ok", fn -> :ok end, 10_000)
    assert StabilityMonitor.state("ok") == :up
  end
end
