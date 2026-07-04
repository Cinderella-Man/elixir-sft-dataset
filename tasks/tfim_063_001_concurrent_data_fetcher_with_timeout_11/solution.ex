  test "all fetches run concurrently, not sequentially" do
    # 5 fetches each taking 100 ms. Sequential would take ~500 ms.
    # Concurrent should finish well under 300 ms.
    sources =
      for i <- 1..5 do
        {i, slow_ok(i, 100)}
      end

    start = System.monotonic_time(:millisecond)
    result = ConcurrentFetcher.fetch_all(sources, 1_000)
    elapsed = System.monotonic_time(:millisecond) - start

    assert Enum.all?(1..5, fn i -> result[i] == {:ok, i} end)
    assert elapsed < 300, "Fetches appear to be sequential (took #{elapsed}ms)"
  end