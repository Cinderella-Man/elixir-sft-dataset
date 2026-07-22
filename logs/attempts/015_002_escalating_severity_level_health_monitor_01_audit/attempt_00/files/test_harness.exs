defmodule HealthMonitorTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!({HealthMonitor, []})
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

  test "a freshly started monitor reports nothing" do
    assert HealthMonitor.report() == %{}
  end

  test "add_probe returns :ok and the probe starts at :ok" do
    assert :ok = HealthMonitor.add_probe("svc", fn -> :ok end, 10_000)
    assert HealthMonitor.level("svc") == :ok
    assert HealthMonitor.report() == %{"svc" => :ok}
  end

  test "add_probe guards a non-positive interval" do
    assert_raise FunctionClauseError, fn ->
      HealthMonitor.add_probe("bad", fn -> :ok end, 0)
    end

    assert :ok = HealthMonitor.add_probe("ok", fn -> :ok end, 10_000)
    assert HealthMonitor.level("ok") == :ok
  end

  test "add_probe guards a non-zero-arity check function" do
    assert_raise FunctionClauseError, fn ->
      HealthMonitor.add_probe("bad", fn _x -> :ok end, 10_000)
    end

    assert :ok = HealthMonitor.add_probe("ok", fn -> :ok end, 10_000)
    assert HealthMonitor.level("ok") == :ok
  end

  test "level and probe_now report unknown probes" do
    assert HealthMonitor.level("nope") == {:error, :not_found}
    assert HealthMonitor.probe_now("nope") == {:error, :not_found}
  end

  test "consecutive failures escalate :ok -> :warning -> :critical, firing on_change per step" do
    test = self()
    hook = fn n, o, nw, r -> send(test, {:changed, n, o, nw, r}) end

    :ok =
      HealthMonitor.add_probe("svc", fn -> {:error, :boom} end, 10_000,
        warn_after: 2,
        crit_after: 3,
        on_change: hook
      )

    # First failure keeps it :ok (count 1 < warn_after 2): no callback.
    assert {:ok, :ok} = HealthMonitor.probe_now("svc")
    refute_receive {:changed, "svc", _, _, _}, 50

    # Second failure reaches warn_after: escalate :ok -> :warning.
    assert {:ok, :warning} = HealthMonitor.probe_now("svc")
    assert_receive {:changed, "svc", :ok, :warning, :boom}, 500

    # Third failure reaches crit_after: escalate :warning -> :critical.
    assert {:ok, :critical} = HealthMonitor.probe_now("svc")
    assert_receive {:changed, "svc", :warning, :critical, :boom}, 500

    assert HealthMonitor.level("svc") == :critical
  end

  test "default thresholds are warn_after 2 and crit_after 4" do
    :ok = HealthMonitor.add_probe("svc", fn -> {:error, :e} end, 10_000)
    assert {:ok, :ok} = HealthMonitor.probe_now("svc")
    assert {:ok, :warning} = HealthMonitor.probe_now("svc")
    assert {:ok, :warning} = HealthMonitor.probe_now("svc")
    assert {:ok, :critical} = HealthMonitor.probe_now("svc")
  end

  test "a success recovers to :ok and fires on_change with a nil reason" do
    test = self()
    hook = fn n, o, nw, r -> send(test, {:changed, n, o, nw, r}) end
    {:ok, box} = Agent.start_link(fn -> {:error, :e} end)
    check = fn -> Agent.get(box, & &1) end

    :ok =
      HealthMonitor.add_probe("svc", check, 10_000,
        warn_after: 1,
        crit_after: 1,
        on_change: hook
      )

    assert {:ok, :critical} = HealthMonitor.probe_now("svc")
    assert_receive {:changed, "svc", :ok, :critical, :e}, 500

    Agent.update(box, fn _ -> :ok end)
    assert {:ok, :ok} = HealthMonitor.probe_now("svc")
    assert_receive {:changed, "svc", :critical, :ok, nil}, 500

    # A success while already :ok changes nothing and fires no callback.
    assert {:ok, :ok} = HealthMonitor.probe_now("svc")
    refute_receive {:changed, "svc", _, _, _}, 50
  end

  test "a success resets the consecutive-failure count" do
    {:ok, box} = Agent.start_link(fn -> {:error, :e} end)
    check = fn -> Agent.get(box, & &1) end
    :ok = HealthMonitor.add_probe("svc", check, 10_000, warn_after: 3, crit_after: 5)

    assert {:ok, :ok} = HealthMonitor.probe_now("svc")
    assert {:ok, :ok} = HealthMonitor.probe_now("svc")

    Agent.update(box, fn _ -> :ok end)
    assert {:ok, :ok} = HealthMonitor.probe_now("svc")

    Agent.update(box, fn _ -> {:error, :e} end)
    assert {:ok, :ok} = HealthMonitor.probe_now("svc")
    assert {:ok, :ok} = HealthMonitor.probe_now("svc")
    assert {:ok, :warning} = HealthMonitor.probe_now("svc")
  end

  test "remove_probe deletes a probe and reports not_found for unknown removals" do
    :ok = HealthMonitor.add_probe("svc", fn -> :ok end, 10_000)
    assert HealthMonitor.report() == %{"svc" => :ok}

    assert :ok = HealthMonitor.remove_probe("svc")
    assert HealthMonitor.level("svc") == {:error, :not_found}
    assert HealthMonitor.report() == %{}

    assert HealthMonitor.remove_probe("svc") == {:error, :not_found}
  end

  test "re-adding a probe resets its level and applies the new config" do
    :ok =
      HealthMonitor.add_probe("svc", fn -> {:error, :x} end, 10_000,
        warn_after: 1,
        crit_after: 1
      )

    assert {:ok, :critical} = HealthMonitor.probe_now("svc")
    assert HealthMonitor.level("svc") == :critical

    :ok =
      HealthMonitor.add_probe("svc", fn -> {:error, :y} end, 10_000,
        warn_after: 1,
        crit_after: 2
      )

    assert HealthMonitor.level("svc") == :ok

    # New crit_after of 2 governs now: one failure is only :warning.
    assert {:ok, :warning} = HealthMonitor.probe_now("svc")
  end

  test "re-adding a probe kills the previous schedule" do
    test = self()

    a = fn ->
      send(test, {:probe, :a})
      :ok
    end

    :ok = HealthMonitor.add_probe("svc", a, 20)
    assert_receive {:probe, :a}, 1_000
    assert_receive {:probe, :a}, 1_000

    b = fn ->
      send(test, {:probe, :b})
      :ok
    end

    :ok = HealthMonitor.add_probe("svc", b, 20)

    flush_probes()
    Process.sleep(200)
    ticks = collect_probes([])

    assert :b in ticks
    refute :a in ticks
  end

  test "remove_probe kills the previous schedule" do
    test = self()

    c = fn ->
      send(test, {:probe, :c})
      :ok
    end

    :ok = HealthMonitor.add_probe("svc", c, 20)
    assert_receive {:probe, :c}, 1_000

    assert :ok = HealthMonitor.remove_probe("svc")

    flush_probes()
    Process.sleep(200)
    assert collect_probes([]) == []
  end

  test "periodic checks run at the configured interval" do
    test = self()

    :ok =
      HealthMonitor.add_probe(
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

  test "probes are independent" do
    :ok =
      HealthMonitor.add_probe("a", fn -> {:error, :x} end, 10_000, warn_after: 1, crit_after: 1)

    :ok = HealthMonitor.add_probe("b", fn -> :ok end, 10_000)

    assert {:ok, :critical} = HealthMonitor.probe_now("a")
    assert {:ok, :ok} = HealthMonitor.probe_now("b")

    assert HealthMonitor.level("a") == :critical
    assert HealthMonitor.level("b") == :ok
    assert HealthMonitor.report() == %{"a" => :critical, "b" => :ok}
  end

  test "unexpected messages do not crash the server" do
    :ok = HealthMonitor.add_probe("svc", fn -> :ok end, 10_000)
    send(HealthMonitor, :garbage)
    send(HealthMonitor, {:more, :garbage})
    assert HealthMonitor.level("svc") == :ok
  end

  test "atom and tuple probe names work and compare by value" do
    :ok = HealthMonitor.add_probe(:svc, fn -> :ok end, 10_000)

    :ok =
      HealthMonitor.add_probe({:svc, 1}, fn -> {:error, :x} end, 10_000,
        warn_after: 1,
        crit_after: 1
      )

    assert HealthMonitor.level(:svc) == :ok
    assert {:ok, :critical} = HealthMonitor.probe_now({:svc, 1})
    assert HealthMonitor.level({:svc, 1}) == :critical
    assert HealthMonitor.report() == %{:svc => :ok, {:svc, 1} => :critical}
  end

  test "registering a probe does not immediately invoke the check function" do
    test = self()

    check = fn ->
      send(test, {:probe, :called})
      :ok
    end

    :ok = HealthMonitor.add_probe("svc", check, 10_000)
    refute_receive {:probe, :called}, 100
    assert HealthMonitor.level("svc") == :ok
  end

  test "a single escalating check fires on_change only once" do
    test = self()
    hook = fn n, o, nw, r -> send(test, {:changed, n, o, nw, r}) end

    :ok =
      HealthMonitor.add_probe("svc", fn -> {:error, :boom} end, 10_000,
        warn_after: 1,
        crit_after: 5,
        on_change: hook
      )

    assert {:ok, :warning} = HealthMonitor.probe_now("svc")
    assert_receive {:changed, "svc", :ok, :warning, :boom}, 500
    refute_receive {:changed, "svc", _, _, _}, 100
  end

  test "add_probe guards a non-integer interval" do
    assert_raise FunctionClauseError, fn ->
      HealthMonitor.add_probe("bad", fn -> :ok end, 10.5)
    end

    assert :ok = HealthMonitor.add_probe("ok", fn -> :ok end, 10_000)
    assert HealthMonitor.level("ok") == :ok
  end
end
