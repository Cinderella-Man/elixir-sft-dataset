  test "fetch_all returns within a reasonable margin of the timeout" do
    sources = [
      {:slow, slow_ok(:never, 10_000)}
    ]

    timeout_ms = 150
    start = System.monotonic_time(:millisecond)
    ConcurrentFetcher.fetch_all(sources, timeout_ms)
    elapsed = System.monotonic_time(:millisecond) - start

    # Should return close to the timeout, not wait for the slow fetch
    assert elapsed < timeout_ms + 200
  end