  test "cleanup keeps a bucket whose TAT is not far enough in the past" do
    {:ok, pid} =
      GcraLimiter.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity,
        cleanup_idle_ms: 1_000_000
      )

    # Burn the burst at t=0 — the bucket's TAT is now in the future, so it is
    # nowhere near `cleanup_idle_ms` in the past and must survive a sweep.
    for _ <- 1..5, do: GcraLimiter.acquire(pid, "k", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(pid, "k", 5.0, 5)

    send(pid, :cleanup)

    # The synchronous call is queued behind :cleanup, so it observes the swept
    # state.  If cleanup wrongly evicted the still-active bucket, this would
    # re-open the full burst and return {:ok, 4}.
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(pid, "k", 5.0, 5)
  end