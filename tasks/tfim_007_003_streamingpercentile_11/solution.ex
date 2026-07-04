  test "percentiles/3 returns a map of q -> value", %{sp: s} do
    for v <- 1..100, do: StreamingPercentile.push(s, "a", v, 100)

    {:ok, results} = StreamingPercentile.percentiles(s, "a", [0.5, 0.95, 0.99])

    # With 100 values (1..100), N=100, rank(q) = q * 99.
    # p50: rank 49.5 → sorted[49]=50, sorted[50]=51, frac=0.5 → 50.5
    # p95: rank 94.05 → sorted[94]=95, sorted[95]=96, frac=0.05 → 95.05
    # p99: rank 98.01 → sorted[98]=99, sorted[99]=100, frac=0.01 → 99.01
    assert close_to(results[0.5], 50.5)
    assert close_to(results[0.95], 95.05)
    assert close_to(results[0.99], 99.01)
  end