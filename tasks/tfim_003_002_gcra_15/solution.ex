  test "cleanup passes happen automatically on the configured interval", %{gl: _gl} do
    test_pid = self()

    # Cleanup consults the injected clock on every pass, so a clock read that
    # is not caused by a call of ours is evidence that a pass ran.
    clock = fn ->
      send(test_pid, :clock_read)
      Clock.now()
    end

    {:ok, pid} =
      GcraLimiter.start_link(
        clock: clock,
        cleanup_interval_ms: 25,
        cleanup_idle_ms: 1_000
      )

    # Give the sweep a bucket to consider, then discard the reads caused by
    # this call.  It has already returned, so it can produce no further reads.
    assert {:ok, 4} = GcraLimiter.acquire(pid, "k", 5.0, 5)
    drain_clock_reads()

    # Nothing sends the server anything from here on: each read below comes
    # from a pass the server scheduled for itself.  Observing two of them also
    # pins that the timer re-arms instead of firing a single time.
    assert_receive :clock_read, 1_000
    assert_receive :clock_read, 1_000
  end