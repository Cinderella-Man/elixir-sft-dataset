  test "idle buckets are dropped by cleanup" do
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

    # A synchronous acquire on an untouched bucket cannot be answered until the
    # cleanup pass queued ahead of it has run, so this doubles as a barrier.
    assert {:ok, 4} = GcraLimiter.acquire(pid, "probe", 5.0, 5)

    # Every swept bucket now behaves exactly like a brand-new one: the first
    # acquire re-opens the full burst budget.
    for i <- 2..100 do
      assert {:ok, 4} = GcraLimiter.acquire(pid, "k:#{i}", 5.0, 5)
    end

    # Fresh bucket after cleanup behaves like new
    assert {:ok, 4} = GcraLimiter.acquire(pid, "k:1", 5.0, 5)
    assert {:ok, 3} = GcraLimiter.acquire(pid, "k:1", 5.0, 5)
    assert {:ok, 2} = GcraLimiter.acquire(pid, "k:1", 5.0, 5)
    assert {:ok, 1} = GcraLimiter.acquire(pid, "k:1", 5.0, 5)
    assert {:ok, 0} = GcraLimiter.acquire(pid, "k:1", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(pid, "k:1", 5.0, 5)
  end