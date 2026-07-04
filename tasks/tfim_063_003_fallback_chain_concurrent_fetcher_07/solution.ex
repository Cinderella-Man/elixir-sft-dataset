  test "sources run concurrently, not sequentially" do
    sources = for i <- 1..5, do: {i, [slow_ok(i, 100)]}

    start = System.monotonic_time(:millisecond)
    result = FallbackFetcher.fetch_all(sources, 1_000)
    elapsed = System.monotonic_time(:millisecond) - start

    assert Enum.all?(1..5, fn i -> result[i] == {:ok, i} end)
    assert elapsed < 300, "fetches appear sequential (took #{elapsed}ms)"
  end