defmodule ClusterMonitorTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!({ClusterMonitor, []})
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

  defp endpoint(box), do: fn -> Agent.get(box, & &1) end

  test "a freshly started monitor snapshots nothing" do
    assert ClusterMonitor.snapshot() == %{}
  end

  test "register_cluster returns :ok, starts :up, and reports healthy == total" do
    funcs = [fn -> :ok end, fn -> :ok end, fn -> :ok end]
    assert :ok = ClusterMonitor.register_cluster("c", funcs, 10_000)
    assert ClusterMonitor.cluster_state("c") == %{status: :up, healthy: 3, total: 3}
    assert ClusterMonitor.snapshot() == %{"c" => :up}
  end

  test "register_cluster guards its arguments" do
    assert_raise FunctionClauseError, fn ->
      ClusterMonitor.register_cluster("c", [], 10_000)
    end

    assert_raise FunctionClauseError, fn ->
      ClusterMonitor.register_cluster("c", [fn -> :ok end], 0)
    end

    assert_raise FunctionClauseError, fn ->
      ClusterMonitor.register_cluster("c", [fn _x -> :ok end], 10_000)
    end

    assert :ok = ClusterMonitor.register_cluster("ok", [fn -> :ok end], 10_000)
    assert ClusterMonitor.cluster_state("ok").status == :up
  end

  test "poll and cluster_state report unknown clusters" do
    assert ClusterMonitor.poll("nope") == {:error, :not_found}
    assert ClusterMonitor.cluster_state("nope") == {:error, :not_found}
  end

  test "the default quorum is a strict majority of endpoints" do
    {:ok, b1} = Agent.start_link(fn -> :ok end)
    {:ok, b2} = Agent.start_link(fn -> :ok end)
    {:ok, b3} = Agent.start_link(fn -> :ok end)
    test = self()

    :ok =
      ClusterMonitor.register_cluster("c", [endpoint(b1), endpoint(b2), endpoint(b3)], 10_000,
        notify: fn n, h -> send(test, {:down, n, h}) end
      )

    # 3 of 3 healthy >= majority (2): up.
    assert {:ok, :up} = ClusterMonitor.poll("c")

    # 2 of 3 healthy >= 2: still up.
    Agent.update(b1, fn _ -> {:error, :x} end)
    assert {:ok, :up} = ClusterMonitor.poll("c")

    # 1 of 3 healthy < 2: down, notify with healthy count 1.
    Agent.update(b2, fn _ -> {:error, :x} end)
    assert {:ok, :down} = ClusterMonitor.poll("c")
    assert_receive {:down, "c", 1}, 500
  end

  test "a custom quorum requires that many healthy endpoints" do
    {:ok, b1} = Agent.start_link(fn -> :ok end)
    {:ok, b2} = Agent.start_link(fn -> :ok end)
    {:ok, b3} = Agent.start_link(fn -> :ok end)

    :ok =
      ClusterMonitor.register_cluster("c", [endpoint(b1), endpoint(b2), endpoint(b3)], 10_000,
        quorum: 3
      )

    assert {:ok, :up} = ClusterMonitor.poll("c")
    Agent.update(b1, fn _ -> {:error, :x} end)
    assert {:ok, :down} = ClusterMonitor.poll("c")
  end

  test "notify fires exactly once per :up -> :down transition" do
    {:ok, b1} = Agent.start_link(fn -> :ok end)
    {:ok, b2} = Agent.start_link(fn -> :ok end)
    test = self()

    :ok =
      ClusterMonitor.register_cluster("c", [endpoint(b1), endpoint(b2)], 10_000,
        quorum: 2,
        notify: fn n, h -> send(test, {:down, n, h}) end
      )

    assert {:ok, :up} = ClusterMonitor.poll("c")
    refute_receive {:down, _, _}, 50

    Agent.update(b1, fn _ -> {:error, :x} end)
    assert {:ok, :down} = ClusterMonitor.poll("c")
    assert_receive {:down, "c", 1}, 500

    # Still down -> no re-notify.
    assert {:ok, :down} = ClusterMonitor.poll("c")
    refute_receive {:down, _, _}, 50

    # Recover -> no notify on up.
    Agent.update(b1, fn _ -> :ok end)
    assert {:ok, :up} = ClusterMonitor.poll("c")
    refute_receive {:down, _, _}, 50

    # Fresh down transition notifies again.
    Agent.update(b1, fn _ -> {:error, :x} end)
    assert {:ok, :down} = ClusterMonitor.poll("c")
    assert_receive {:down, "c", 1}, 500
  end

  test "cluster_state reports healthy and total after a poll" do
    {:ok, b1} = Agent.start_link(fn -> :ok end)
    {:ok, b2} = Agent.start_link(fn -> :ok end)
    {:ok, b3} = Agent.start_link(fn -> :ok end)

    :ok =
      ClusterMonitor.register_cluster("c", [endpoint(b1), endpoint(b2), endpoint(b3)], 10_000,
        quorum: 2
      )

    Agent.update(b1, fn _ -> {:error, :x} end)
    assert {:ok, :up} = ClusterMonitor.poll("c")
    assert ClusterMonitor.cluster_state("c") == %{status: :up, healthy: 2, total: 3}
  end

  test "re-registering a cluster resets status and applies the new config" do
    {:ok, b1} = Agent.start_link(fn -> {:error, :x} end)
    :ok = ClusterMonitor.register_cluster("c", [endpoint(b1)], 10_000, quorum: 1)
    assert {:ok, :down} = ClusterMonitor.poll("c")
    assert ClusterMonitor.cluster_state("c").status == :down

    # Re-register with two healthy endpoints and quorum 2.
    :ok = ClusterMonitor.register_cluster("c", [fn -> :ok end, fn -> :ok end], 10_000, quorum: 2)
    assert ClusterMonitor.cluster_state("c") == %{status: :up, healthy: 2, total: 2}
    assert {:ok, :up} = ClusterMonitor.poll("c")
  end

  test "re-registering a cluster kills the previous schedule" do
    test = self()

    a = fn ->
      send(test, {:probe, :a})
      :ok
    end

    :ok = ClusterMonitor.register_cluster("c", [a], 20)
    assert_receive {:probe, :a}, 1_000
    assert_receive {:probe, :a}, 1_000

    b = fn ->
      send(test, {:probe, :b})
      :ok
    end

    :ok = ClusterMonitor.register_cluster("c", [b], 20)

    flush_probes()
    Process.sleep(200)
    ticks = collect_probes([])

    assert :b in ticks
    refute :a in ticks
  end

  test "unregister removes a cluster and kills its schedule" do
    test = self()

    c = fn ->
      send(test, {:probe, :c})
      :ok
    end

    :ok = ClusterMonitor.register_cluster("c", [c], 20)
    assert_receive {:probe, :c}, 1_000

    assert :ok = ClusterMonitor.unregister("c")
    assert ClusterMonitor.cluster_state("c") == {:error, :not_found}
    assert ClusterMonitor.unregister("c") == {:error, :not_found}

    flush_probes()
    Process.sleep(200)
    assert collect_probes([]) == []
  end

  test "periodic polling runs at the configured interval" do
    test = self()

    :ok =
      ClusterMonitor.register_cluster(
        "c",
        [
          fn ->
            send(test, {:probe, :a})
            :ok
          end
        ],
        20
      )

    assert_receive {:probe, :a}, 1_000
    assert_receive {:probe, :a}, 1_000
  end

  test "clusters are independent" do
    :ok = ClusterMonitor.register_cluster("a", [fn -> {:error, :x} end], 10_000, quorum: 1)
    :ok = ClusterMonitor.register_cluster("b", [fn -> :ok end], 10_000, quorum: 1)

    assert {:ok, :down} = ClusterMonitor.poll("a")
    assert {:ok, :up} = ClusterMonitor.poll("b")
    assert ClusterMonitor.snapshot() == %{"a" => :down, "b" => :up}
  end

  test "unexpected messages do not crash the server" do
    :ok = ClusterMonitor.register_cluster("c", [fn -> :ok end], 10_000)
    send(ClusterMonitor, :garbage)
    send(ClusterMonitor, {:more, :garbage})
    assert ClusterMonitor.cluster_state("c").status == :up
  end

  test "atom and tuple cluster names work and compare by value" do
    :ok = ClusterMonitor.register_cluster(:svc, [fn -> :ok end], 10_000, quorum: 1)
    :ok = ClusterMonitor.register_cluster({:svc, 1}, [fn -> {:error, :x} end], 10_000, quorum: 1)

    assert ClusterMonitor.cluster_state(:svc).status == :up
    assert {:ok, :down} = ClusterMonitor.poll({:svc, 1})
    assert ClusterMonitor.snapshot() == %{:svc => :up, {:svc, 1} => :down}
  end

  test "a scheduled poll fires notify on an up to down transition" do
    test = self()
    down = fn -> {:error, :x} end

    :ok =
      ClusterMonitor.register_cluster("c", [down], 30,
        quorum: 1,
        notify: fn n, h -> send(test, {:down, n, h}) end
      )

    # No poll/1 call: the periodic timer alone must poll, transition up -> down,
    # and fire notify exactly once with this poll's healthy count (0).
    assert_receive {:down, "c", 0}, 1_000
  end

  test "registration defers the first poll until one interval elapses" do
    test = self()

    probe = fn ->
      send(test, {:probe, :first})
      :ok
    end

    :ok = ClusterMonitor.register_cluster("c", [probe], 200)

    # Registration itself must not call any endpoint before the interval passes.
    refute_receive {:probe, :first}, 60
    # The first poll then arrives after one interval.
    assert_receive {:probe, :first}, 1_000
  end
end
