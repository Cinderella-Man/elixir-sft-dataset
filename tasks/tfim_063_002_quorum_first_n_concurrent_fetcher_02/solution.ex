  test "returns as soon as the quorum of successes is reached and cancels the rest" do
    sources = [
      {:a, slow_ok(:ra, 20)},
      {:b, slow_ok(:rb, 20)},
      {:c, slow_ok(:rc, 20)},
      {:d, slow_ok(:rd, 3_000)},
      {:e, slow_ok(:re, 3_000)}
    ]

    start = System.monotonic_time(:millisecond)
    result = QuorumFetcher.fetch_first(sources, 3, 1_000)
    elapsed = System.monotonic_time(:millisecond) - start

    assert result[:a] == {:ok, :ra}
    assert result[:b] == {:ok, :rb}
    assert result[:c] == {:ok, :rc}
    assert result[:d] == {:error, :cancelled}
    assert result[:e] == {:error, :cancelled}
    assert elapsed < 500, "should not wait for the slow sources (took #{elapsed}ms)"
  end