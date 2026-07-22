defmodule WindowMonitorTest do
  use ExUnit.Case, async: false

  # Deterministic scripted probe: yields the given results in order on successive
  # calls; once a single element remains, that element repeats forever.
  defp script(list) do
    {:ok, pid} = Agent.start_link(fn -> list end)
    fn -> next(pid) end
  end

  defp next(pid) do
    Agent.get_and_update(pid, fn
      [x] -> {x, [x]}
      [x | rest] -> {x, rest}
      [] -> {:ok, []}
    end)
  end

  setup do
    {:ok, server} = WindowMonitor.start_link([])
    %{server: server}
  end

  test "watch returns :ok, a new service is :up, and report starts empty", %{server: server} do
    assert WindowMonitor.report(server) == %{}
    assert :ok = WindowMonitor.watch(server, "svc", script([:ok]))
    assert {:ok, :up} = WindowMonitor.health(server, "svc")
    assert WindowMonitor.report(server) == %{"svc" => :up}
  end

  test "report lists all watched services", %{server: server} do
    :ok = WindowMonitor.watch(server, "a", script([:ok]))
    :ok = WindowMonitor.watch(server, "b", script([:ok]))
    assert WindowMonitor.report(server) == %{"a" => :up, "b" => :up}
  end

  test "health and probe_now on an unknown service return {:error, :not_found}", %{
    server: server
  } do
    assert {:error, :not_found} = WindowMonitor.health(server, "nope")
    assert {:error, :not_found} = WindowMonitor.probe_now(server, "nope")
  end

  test "probe_now returns {:ok, status}", %{server: server} do
    :ok = WindowMonitor.watch(server, "svc", script([:ok]))
    assert {:ok, :up} = WindowMonitor.probe_now(server, "svc")
  end

  test "service goes down when window failure count reaches threshold, notifying once",
       %{server: server} do
    me = self()
    on_change = fn n, s -> send(me, {:change, n, s}) end

    :ok =
      WindowMonitor.watch(server, "svc", script([{:error, :boom}]),
        window: 5,
        threshold: 3,
        on_change: on_change
      )

    assert {:ok, :up} = WindowMonitor.probe_now(server, "svc")
    assert {:ok, :up} = WindowMonitor.probe_now(server, "svc")
    refute_receive {:change, _, _}, 50

    assert {:ok, :down} = WindowMonitor.probe_now(server, "svc")
    assert_receive {:change, "svc", :down}

    # Still failing while already down: no further notification.
    assert {:ok, :down} = WindowMonitor.probe_now(server, "svc")
    refute_receive {:change, _, _}, 100
  end

  test "threshold and window default to 3 and 5", %{server: server} do
    :ok = WindowMonitor.watch(server, "svc", script([{:error, :boom}]))
    assert {:ok, :up} = WindowMonitor.probe_now(server, "svc")
    assert {:ok, :up} = WindowMonitor.probe_now(server, "svc")
    assert {:ok, :down} = WindowMonitor.probe_now(server, "svc")
  end

  test "non-consecutive failures within the window still trip the threshold", %{server: server} do
    # error, ok, error, ok, error -> 3 failures in a 5-wide window -> down
    seq = [{:error, :boom}, :ok, {:error, :boom}, :ok, {:error, :boom}, :ok]

    :ok = WindowMonitor.watch(server, "svc", script(seq), window: 5, threshold: 3)

    assert {:ok, :up} = WindowMonitor.probe_now(server, "svc")
    assert {:ok, :up} = WindowMonitor.probe_now(server, "svc")
    assert {:ok, :up} = WindowMonitor.probe_now(server, "svc")
    assert {:ok, :up} = WindowMonitor.probe_now(server, "svc")
    assert {:ok, :down} = WindowMonitor.probe_now(server, "svc")
  end

  test "a service recovers automatically as failures slide out of the window", %{server: server} do
    me = self()
    on_change = fn n, s -> send(me, {:change, n, s}) end

    seq = [{:error, :boom}, {:error, :boom}, {:error, :boom}, :ok, :ok, :ok, :ok]

    :ok =
      WindowMonitor.watch(server, "svc", script(seq),
        window: 5,
        threshold: 3,
        on_change: on_change
      )

    assert {:ok, :up} = WindowMonitor.probe_now(server, "svc")
    assert {:ok, :up} = WindowMonitor.probe_now(server, "svc")
    assert {:ok, :down} = WindowMonitor.probe_now(server, "svc")
    assert_receive {:change, "svc", :down}

    assert {:ok, :down} = WindowMonitor.probe_now(server, "svc")
    assert {:ok, :down} = WindowMonitor.probe_now(server, "svc")
    # 6th probe: window now holds only 2 failures -> back up.
    assert {:ok, :up} = WindowMonitor.probe_now(server, "svc")
    assert_receive {:change, "svc", :up}
    refute_receive {:change, _, _}, 100
  end

  test "services are independent", %{server: server} do
    me = self()
    on_change = fn n, s -> send(me, {:change, n, s}) end

    :ok =
      WindowMonitor.watch(server, "a", script([{:error, :boom}]),
        threshold: 1,
        on_change: on_change
      )

    :ok = WindowMonitor.watch(server, "b", script([:ok]), on_change: on_change)

    assert {:ok, :down} = WindowMonitor.probe_now(server, "a")
    assert_receive {:change, "a", :down}
    assert {:ok, :up} = WindowMonitor.health(server, "b")
    assert WindowMonitor.report(server) == %{"a" => :down, "b" => :up}
    refute_receive {:change, "b", _}, 50
  end

  test "automatic interval probing drives a service down", %{server: server} do
    me = self()
    on_change = fn n, s -> send(me, {:change, n, s}) end

    :ok =
      WindowMonitor.watch(server, "auto", script([{:error, :boom}]),
        threshold: 1,
        interval: 20,
        on_change: on_change
      )

    assert_receive {:change, "auto", :down}, 2_000
    assert {:ok, :down} = WindowMonitor.health(server, "auto")
    refute_receive {:change, _, _}, 200
  end

  test "re-watching a name resets its state", %{server: server} do
    :ok = WindowMonitor.watch(server, "svc", script([{:error, :boom}]), threshold: 1)
    assert {:ok, :down} = WindowMonitor.probe_now(server, "svc")

    :ok = WindowMonitor.watch(server, "svc", script([:ok]))
    assert {:ok, :up} = WindowMonitor.health(server, "svc")
    assert WindowMonitor.report(server) == %{"svc" => :up}
  end

  test "unexpected messages are ignored and do not disturb state", %{server: server} do
    :ok = WindowMonitor.watch(server, "svc", script([:ok]))
    send(server, :hello)
    send(server, {:weird, 1, 2})
    assert {:ok, :up} = WindowMonitor.health(server, "svc")
    assert Process.alive?(server)
  end

  test "a manual (default interval) service is never probed automatically", %{server: server} do
    # Probe would fail with threshold 1, so any automatic probe would flip it :down.
    me = self()
    on_change = fn n, s -> send(me, {:change, n, s}) end

    :ok =
      WindowMonitor.watch(server, "svc", script([{:error, :boom}]),
        threshold: 1,
        on_change: on_change
      )

    # No :interval given -> :manual; nothing should probe it on its own.
    refute_receive {:change, _, _}, 150
    assert {:ok, :up} = WindowMonitor.health(server, "svc")
    assert WindowMonitor.report(server) == %{"svc" => :up}
  end

  test "probe_now only probes the named service, leaving others untouched", %{server: server} do
    :ok = WindowMonitor.watch(server, "a", script([{:error, :boom}]), threshold: 1)
    :ok = WindowMonitor.watch(server, "b", script([{:error, :boom}]), threshold: 1)

    assert {:ok, :down} = WindowMonitor.probe_now(server, "a")
    # "b" was never probed, so it must still be :up with an empty window.
    assert {:ok, :up} = WindowMonitor.health(server, "b")
    assert WindowMonitor.report(server) == %{"a" => :down, "b" => :up}
  end
end
