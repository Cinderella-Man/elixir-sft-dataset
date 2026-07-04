  test "idle buckets are dropped by cleanup" do
    # Removed the redundant `start_supervised!({Clock, 0})` here

    {:ok, pid} =
      GcraLimiter.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity,
        cleanup_idle_ms: 1_000
      )

    # Touch 100 buckets
    for i <- 1..100, do: GcraLimiter.acquire(pid, "k:#{i}", 5.0, 5)

    # Advance well past cleanup_idle_ms
    Clock.advance(2_000)

    send(pid, :cleanup)
    :sys.get_state(pid)

    state = :sys.get_state(pid)
    assert map_size(state.buckets) == 0

    # Fresh bucket after cleanup behaves like new
    assert {:ok, 4} = GcraLimiter.acquire(pid, "k:1", 5.0, 5)
  end