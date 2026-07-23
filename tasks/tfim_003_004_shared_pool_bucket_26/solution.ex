  test "key_level is a pure query: it never rewrites stored capacity or rate" do
    {:ok, sp} =
      SharedPoolBucket.start_link(
        global_capacity: 100,
        global_refill_rate: 1.0,
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    # Define the bucket per-acquire at capacity 5 and drain it fully
    # (a tiny refill rate keeps the refill negligible at the fake clock's 0).
    {:ok, 0, _} = SharedPoolBucket.acquire(sp, "k", 5, 0.001, 5)

    # Query at a WILDLY different capacity: reported against 100...
    assert {:ok, 0} = SharedPoolBucket.key_level(sp, "k", 100, 0.001)

    # ...but the stored bucket is untouched: re-acquiring at the original
    # capacity still sees the drained 5-token bucket (nothing to give), and
    # a plain re-query at capacity 5 reports the same drained level.
    assert {:error, :key_empty, _retry} = SharedPoolBucket.acquire(sp, "k", 5, 0.001, 1)
    assert {:ok, 0} = SharedPoolBucket.key_level(sp, "k", 5, 0.001)
  end