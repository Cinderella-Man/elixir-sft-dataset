  test "periodic cleanup fires automatically on a real interval" do
    # A real, short interval means the sweep runs on its own timer, driven by
    # the default wall-clock. The lease deadline passes on its own, and an
    # automatic sweep returns the bucket to fresh behaviour.
    server = start_supervised!({LeaseBucket, cleanup_interval_ms: 25})

    {:ok, _lease, 0} = LeaseBucket.acquire_lease(server, "k", 2, 1000.0, 2, 20)

    # Poll a generous window (well over 20× the interval) for the automatic
    # outcome, never sending :cleanup ourselves.
    deadline = System.monotonic_time(:millisecond) + 1_000

    assert :ok =
             wait_until(
               fn -> LeaseBucket.active_leases(server, "k") == {:ok, 0} end,
               deadline
             )

    # Back to fresh: a full-capacity reservation succeeds again.
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(server, "k", 2, 1000.0, 2, 20)
  end