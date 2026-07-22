defmodule DepMonitorTest do
  use ExUnit.Case, async: false

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
    {:ok, server} = DepMonitor.start_link([])
    %{server: server}
  end

  test "add_node returns :ok; a new node is up (own and effective); snapshot", %{server: server} do
    assert DepMonitor.snapshot(server) == %{}
    assert :ok = DepMonitor.add_node(server, "n", script([:ok]))
    assert {:ok, :up} = DepMonitor.direct_status(server, "n")
    assert {:ok, :up} = DepMonitor.effective_status(server, "n")
    assert DepMonitor.snapshot(server) == %{"n" => :up}
  end

  test "unknown nodes return {:error, :not_found}", %{server: server} do
    assert {:error, :not_found} = DepMonitor.direct_status(server, "x")
    assert {:error, :not_found} = DepMonitor.effective_status(server, "x")
    assert {:error, :not_found} = DepMonitor.check(server, "x")
  end

  test "own status goes down after consecutive-failure threshold", %{server: server} do
    :ok = DepMonitor.add_node(server, "n", script([{:error, :boom}]), threshold: 3)
    assert {:ok, :up} = DepMonitor.check(server, "n")
    assert {:ok, :up} = DepMonitor.check(server, "n")
    assert {:ok, :down} = DepMonitor.check(server, "n")
    assert {:ok, :down} = DepMonitor.direct_status(server, "n")
  end

  test "threshold defaults to 3", %{server: server} do
    :ok = DepMonitor.add_node(server, "n", script([{:error, :boom}]))
    assert {:ok, :up} = DepMonitor.check(server, "n")
    assert {:ok, :up} = DepMonitor.check(server, "n")
    assert {:ok, :down} = DepMonitor.check(server, "n")
  end

  test "a consecutive-failure run is broken by any success", %{server: server} do
    seq = [{:error, :boom}, {:error, :boom}, :ok, {:error, :boom}, {:error, :boom}]
    :ok = DepMonitor.add_node(server, "n", script(seq), threshold: 3)
    for _ <- 1..5, do: assert({:ok, _} = DepMonitor.check(server, "n"))
    assert {:ok, :up} = DepMonitor.direct_status(server, "n")
  end

  test "a dependency going down cascades to dependents' effective status", %{server: server} do
    me = self()
    on_b = fn n, s -> send(me, {:eff, n, s}) end
    on_a = fn n, s -> send(me, {:eff, n, s}) end

    :ok =
      DepMonitor.add_node(server, "B", script([{:error, :boom}]), threshold: 1, on_change: on_b)

    :ok =
      DepMonitor.add_node(server, "A", script([:ok]),
        depends_on: ["B"],
        on_change: on_a
      )

    assert {:ok, :up} = DepMonitor.effective_status(server, "A")

    # Take B down; A's effective status must follow even though A's own probe is fine.
    assert {:ok, :down} = DepMonitor.check(server, "B")
    assert {:ok, :down} = DepMonitor.effective_status(server, "A")
    assert {:ok, :up} = DepMonitor.direct_status(server, "A")

    assert_receive {:eff, "B", :down}
    assert_receive {:eff, "A", :down}
  end

  test "recovery of a dependency cascades back up", %{server: server} do
    me = self()
    on_change = fn n, s -> send(me, {:eff, n, s}) end

    :ok =
      DepMonitor.add_node(server, "B", script([{:error, :boom}, :ok]),
        threshold: 1,
        on_change: on_change
      )

    :ok = DepMonitor.add_node(server, "A", script([:ok]), depends_on: ["B"], on_change: on_change)

    assert {:ok, :down} = DepMonitor.check(server, "B")
    assert_receive {:eff, "B", :down}
    assert_receive {:eff, "A", :down}

    assert {:ok, :up} = DepMonitor.check(server, "B")
    assert {:ok, :up} = DepMonitor.effective_status(server, "A")
    assert_receive {:eff, "B", :up}
    assert_receive {:eff, "A", :up}
  end

  test "cascades are transitive across a chain A -> B -> C", %{server: server} do
    me = self()
    on_change = fn n, s -> send(me, {:eff, n, s}) end

    :ok =
      DepMonitor.add_node(server, "C", script([{:error, :boom}]),
        threshold: 1,
        on_change: on_change
      )

    :ok = DepMonitor.add_node(server, "B", script([:ok]), depends_on: ["C"], on_change: on_change)
    :ok = DepMonitor.add_node(server, "A", script([:ok]), depends_on: ["B"], on_change: on_change)

    assert {:ok, :down} = DepMonitor.check(server, "C")
    assert {:ok, :down} = DepMonitor.effective_status(server, "B")
    assert {:ok, :down} = DepMonitor.effective_status(server, "A")

    assert_receive {:eff, "C", :down}
    assert_receive {:eff, "B", :down}
    assert_receive {:eff, "A", :down}
  end

  test "unrelated nodes are independent", %{server: server} do
    me = self()
    on_change = fn n, s -> send(me, {:eff, n, s}) end

    :ok =
      DepMonitor.add_node(server, "B", script([{:error, :boom}]),
        threshold: 1,
        on_change: on_change
      )

    :ok = DepMonitor.add_node(server, "A", script([:ok]), depends_on: ["B"], on_change: on_change)
    :ok = DepMonitor.add_node(server, "C", script([:ok]), on_change: on_change)

    assert {:ok, :down} = DepMonitor.check(server, "B")
    assert {:ok, :up} = DepMonitor.effective_status(server, "C")
    refute_receive {:eff, "C", _}, 50
    assert DepMonitor.snapshot(server) == %{"A" => :down, "B" => :down, "C" => :up}
  end

  test "automatic interval probing drives a node's own status down", %{server: server} do
    me = self()
    on_change = fn n, s -> send(me, {:eff, n, s}) end

    :ok =
      DepMonitor.add_node(server, "auto", script([{:error, :boom}]),
        threshold: 1,
        interval: 20,
        on_change: on_change
      )

    assert_receive {:eff, "auto", :down}, 2_000
    assert {:ok, :down} = DepMonitor.effective_status(server, "auto")
  end

  test "re-adding a node resets it", %{server: server} do
    :ok = DepMonitor.add_node(server, "n", script([{:error, :boom}]), threshold: 1)
    assert {:ok, :down} = DepMonitor.check(server, "n")
    :ok = DepMonitor.add_node(server, "n", script([:ok]))
    assert {:ok, :up} = DepMonitor.direct_status(server, "n")
  end

  test "unexpected messages are ignored", %{server: server} do
    :ok = DepMonitor.add_node(server, "n", script([:ok]))
    send(server, :hello)
    send(server, {:weird, 1, 2})
    assert {:ok, :up} = DepMonitor.effective_status(server, "n")
    assert Process.alive?(server)
  end

  test "adding a node never invokes its on_change callback", %{server: server} do
    me = self()
    on_change = fn n, s -> send(me, {:eff, n, s}) end
    :ok = DepMonitor.add_node(server, "n", script([:ok]), on_change: on_change)
    refute_receive {:eff, _, _}, 50
    assert {:ok, :up} = DepMonitor.effective_status(server, "n")
  end

  test "a dependency that was never added is treated as effectively up", %{server: server} do
    :ok = DepMonitor.add_node(server, "A", script([:ok]), depends_on: ["ghost"])
    assert {:ok, :up} = DepMonitor.effective_status(server, "A")
    assert DepMonitor.snapshot(server) == %{"A" => :up}
  end

  test "check returns the probed node's effective status", %{server: server} do
    :ok = DepMonitor.add_node(server, "n", script([{:error, :boom}]), threshold: 1)
    assert {:ok, :down} = DepMonitor.check(server, "n")
    assert {:ok, :down} = DepMonitor.effective_status(server, "n")
  end

  test "manual nodes are never probed automatically", %{server: server} do
    me = self()
    on_change = fn n, s -> send(me, {:eff, n, s}) end

    :ok =
      DepMonitor.add_node(server, "n", script([{:error, :boom}]),
        threshold: 1,
        on_change: on_change
      )

    refute_receive {:eff, "n", _}, 100
    assert {:ok, :up} = DepMonitor.direct_status(server, "n")
  end
end
