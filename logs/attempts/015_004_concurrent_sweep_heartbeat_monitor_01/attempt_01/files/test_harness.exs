defmodule AsyncMonitorTest do
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
    {:ok, server} = AsyncMonitor.start_link([])
    %{server: server}
  end

  test "enroll returns :ok, a new service is up, overview starts empty", %{server: server} do
    assert AsyncMonitor.overview(server) == %{}
    assert :ok = AsyncMonitor.enroll(server, "svc", script([:ok]))
    assert {:ok, :up} = AsyncMonitor.status(server, "svc")
    assert AsyncMonitor.overview(server) == %{"svc" => :up}
  end

  test "status of an unknown service is {:error, :not_found}", %{server: server} do
    assert {:error, :not_found} = AsyncMonitor.status(server, "nope")
  end

  test "sweep with no services returns :ok", %{server: server} do
    assert :ok = AsyncMonitor.sweep(server)
  end

  test "a sweep runs one probe per service and applies results", %{server: server} do
    me = self()
    on_change = fn n, s -> send(me, {:change, n, s}) end

    :ok =
      AsyncMonitor.enroll(server, "svc", script([{:error, :boom}]),
        threshold: 3,
        on_change: on_change
      )

    assert :ok = AsyncMonitor.sweep(server)
    assert :ok = AsyncMonitor.sweep(server)
    assert {:ok, :up} = AsyncMonitor.status(server, "svc")
    refute_receive {:change, _, _}, 50

    assert :ok = AsyncMonitor.sweep(server)
    assert {:ok, :down} = AsyncMonitor.status(server, "svc")
    assert_receive {:change, "svc", :down}

    assert :ok = AsyncMonitor.sweep(server)
    assert {:ok, :down} = AsyncMonitor.status(server, "svc")
    refute_receive {:change, _, _}, 100
  end

  test "threshold defaults to 3", %{server: server} do
    :ok = AsyncMonitor.enroll(server, "svc", script([{:error, :boom}]))
    assert :ok = AsyncMonitor.sweep(server)
    assert :ok = AsyncMonitor.sweep(server)
    assert {:ok, :up} = AsyncMonitor.status(server, "svc")
    assert :ok = AsyncMonitor.sweep(server)
    assert {:ok, :down} = AsyncMonitor.status(server, "svc")
  end

  test "a healthy probe resets the consecutive-failure count", %{server: server} do
    seq = [{:error, :boom}, {:error, :boom}, :ok, {:error, :boom}, {:error, :boom}]
    :ok = AsyncMonitor.enroll(server, "svc", script(seq), threshold: 3)
    for _ <- 1..5, do: assert(:ok = AsyncMonitor.sweep(server))
    assert {:ok, :up} = AsyncMonitor.status(server, "svc")
  end

  test "a service recovers to up and notifies", %{server: server} do
    me = self()
    on_change = fn n, s -> send(me, {:change, n, s}) end

    seq = [{:error, :boom}, {:error, :boom}, {:error, :boom}, :ok]
    :ok = AsyncMonitor.enroll(server, "svc", script(seq), threshold: 3, on_change: on_change)

    for _ <- 1..3, do: assert(:ok = AsyncMonitor.sweep(server))
    assert {:ok, :down} = AsyncMonitor.status(server, "svc")
    assert_receive {:change, "svc", :down}

    assert :ok = AsyncMonitor.sweep(server)
    assert {:ok, :up} = AsyncMonitor.status(server, "svc")
    assert_receive {:change, "svc", :up}
  end

  test "services are independent within a sweep", %{server: server} do
    me = self()
    on_change = fn n, s -> send(me, {:change, n, s}) end

    :ok =
      AsyncMonitor.enroll(server, "a", script([{:error, :boom}]),
        threshold: 1,
        on_change: on_change
      )

    :ok = AsyncMonitor.enroll(server, "b", script([:ok]), on_change: on_change)

    assert :ok = AsyncMonitor.sweep(server)
    assert {:ok, :down} = AsyncMonitor.status(server, "a")
    assert {:ok, :up} = AsyncMonitor.status(server, "b")
    assert AsyncMonitor.overview(server) == %{"a" => :down, "b" => :up}
    assert_receive {:change, "a", :down}
    refute_receive {:change, "b", _}, 50
  end

  test "probes within a sweep run concurrently in separate processes", %{server: server} do
    me = self()

    # Each probe announces its own process pid, then blocks until told to continue.
    # Both announcements can only arrive if both probes were dispatched before the
    # sweep waited for either to finish.
    rendezvous = fn tag ->
      fn ->
        send(me, {:started, tag, self()})

        receive do
          :go -> :ok
        end
      end
    end

    :ok = AsyncMonitor.enroll(server, "a", rendezvous.(:a))
    :ok = AsyncMonitor.enroll(server, "b", rendezvous.(:b))

    sweeper = Task.async(fn -> AsyncMonitor.sweep(server) end)

    assert_receive {:started, :a, pid_a}, 1_000
    assert_receive {:started, :b, pid_b}, 1_000

    send(pid_a, :go)
    send(pid_b, :go)

    assert :ok = Task.await(sweeper, 1_000)
    assert {:ok, :up} = AsyncMonitor.status(server, "a")
    assert {:ok, :up} = AsyncMonitor.status(server, "b")
  end

  test "a probe that raises counts as a failure and does not crash the server", %{server: server} do
    :ok = AsyncMonitor.enroll(server, "svc", fn -> raise "boom" end, threshold: 1)
    assert :ok = AsyncMonitor.sweep(server)
    assert {:ok, :down} = AsyncMonitor.status(server, "svc")
    assert Process.alive?(server)
  end

  test "re-enrolling a name resets its state", %{server: server} do
    :ok = AsyncMonitor.enroll(server, "svc", script([{:error, :boom}]), threshold: 1)
    assert :ok = AsyncMonitor.sweep(server)
    assert {:ok, :down} = AsyncMonitor.status(server, "svc")

    :ok = AsyncMonitor.enroll(server, "svc", script([:ok]))
    assert {:ok, :up} = AsyncMonitor.status(server, "svc")
    assert :ok = AsyncMonitor.sweep(server)
    assert {:ok, :up} = AsyncMonitor.status(server, "svc")
  end

  test "a service with no :on_change can transition without crashing", %{server: server} do
    :ok = AsyncMonitor.enroll(server, "svc", script([{:error, :boom}]), threshold: 1)
    assert :ok = AsyncMonitor.sweep(server)
    assert {:ok, :down} = AsyncMonitor.status(server, "svc")
    assert Process.alive?(server)
  end

  test "unexpected messages are ignored and do not disturb state", %{server: server} do
    :ok = AsyncMonitor.enroll(server, "svc", script([:ok]))
    send(server, :hello)
    send(server, {:weird, 1, 2})
    assert {:ok, :up} = AsyncMonitor.status(server, "svc")
    assert :ok = AsyncMonitor.sweep(server)
    assert Process.alive?(server)
  end

  test "unexpected casts are ignored and do not crash the server", %{server: server} do
    # start_link links the server to this test process; trap exits so a crash in
    # the server (e.g. a gutted handle_cast) surfaces as an assertion failure here
    # rather than silently killing the test process.
    Process.flag(:trap_exit, true)

    :ok = AsyncMonitor.enroll(server, "svc", script([{:error, :boom}]), threshold: 1)

    assert :ok = GenServer.cast(server, :hello)
    assert :ok = GenServer.cast(server, {:weird, 1, 2})

    # A subsequent synchronous call is processed only after the earlier casts, so
    # if handle_cast/2 crashed the server this call (and thus the test) fails.
    assert {:ok, :up} = AsyncMonitor.status(server, "svc")
    assert Process.alive?(server)

    # State is untouched by the casts: the service still needs one failing sweep
    # (threshold 1) to go down, proving the casts neither advanced nor reset it.
    assert :ok = AsyncMonitor.sweep(server)
    assert {:ok, :down} = AsyncMonitor.status(server, "svc")
    assert Process.alive?(server)

    refute_received {:EXIT, ^server, _reason}
  end
end
