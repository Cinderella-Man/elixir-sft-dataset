  test "if the leader process is hard-killed, followers retry via the DOWN monitor",
       %{cl: cl} do
    parent = self()

    # The leader announces its pid then blocks forever; a hard kill means no
    # rescue clause can run, so ONLY the GenServer's Process.monitor/DOWN
    # handling (in handle_info/2) can unblock a parked follower.
    blocking = fn ->
      send(parent, {:leader_pid, self()})
      Process.sleep(:infinity)
    end

    # Unlinked spawn so killing the leader does not take down the test process.
    leader_pid = spawn(fn -> CacheLayer.fetch(cl, :t, :down_key, blocking) end)

    receive do
      {:leader_pid, ^leader_pid} -> :ok
    after
      1_000 -> flunk("leader never started")
    end

    # A follower parks inside the GenServer, waiting on the leader's result.
    follower =
      Task.async(fn -> CacheLayer.fetch(cl, :t, :down_key, fn -> :recovered end) end)

    # Give the follower time to register as a waiter before the leader dies.
    Process.sleep(80)

    # Hard kill: untrappable, so the leader cannot report {:fail, ...}. The only
    # thing that can rescue the follower is the monitored :DOWN message routed
    # through handle_info/2. If that clause is gutted, the follower hangs and
    # this assertion times out.
    Process.exit(leader_pid, :kill)

    assert {:ok, :recovered} = Task.await(follower, 2_000)

    # The recovered value must now be cached without recomputation.
    assert {:ok, :recovered} = CacheLayer.fetch(cl, :t, :down_key, fn -> :other end)
  end