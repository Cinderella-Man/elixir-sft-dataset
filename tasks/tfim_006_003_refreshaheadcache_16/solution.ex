  test "sweeping an entry mid-refresh discards the late result, no resurrect", %{c: c} do
    test_pid = self()

    # This loader blocks until released, keeping a refresh in flight
    # deterministically while we sweep the entry out from under it.
    loader = fn ->
      send(test_pid, {:task, self()})

      receive do
        :release -> :ok
      end

      :late_value
    end

    :ok = RefreshAheadCache.put(c, :a, :v1, 1_000, loader)

    Clock.advance(850)
    assert {:ok, :v1} = RefreshAheadCache.get(c, :a)
    assert_receive {:task, task_pid}
    assert %{refreshes_in_flight: 1} = RefreshAheadCache.stats(c)

    # Hard-expire the entry, then sweep it while its refresh is still running.
    Clock.advance(200)
    send(c, :sweep)
    assert %{entries: 0} = RefreshAheadCache.stats(c)

    # Release the refresh and wait for its task to fully exit, which guarantees
    # the {:refresh_complete, ...} message is already in the server mailbox.
    ref = Process.monitor(task_pid)
    send(task_pid, :release)
    assert_receive {:DOWN, ^ref, :process, ^task_pid, _}

    # The following synchronous calls drain past that stale message: it must be
    # discarded and must NOT resurrect the swept entry.
    assert :miss = RefreshAheadCache.get(c, :a)
    assert %{entries: 0} = RefreshAheadCache.stats(c)
  end