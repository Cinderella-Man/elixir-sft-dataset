  test "percentile between ranks uses linear interpolation", %{sp: s} do
    for v <- 1..10, do: StreamingPercentile.push(s, "a", v, 10)

    # sorted = 1..10 (N=10). rank = 0.25 * 9 = 2.25
    # lo=2, hi=3, sorted[2]=3, sorted[3]=4, frac=0.25
    # result = 3 + 0.25 * (4 - 3) = 3.25
    {:ok, p25} = StreamingPercentile.percentile(s, "a", 0.25)
    assert close_to(p25, 3.25)

    # p95: rank = 0.95 * 9 = 8.55
    # lo=8, hi=9, sorted[8]=9, sorted[9]=10, frac=0.55
    # result = 9 + 0.55*(10-9) = 9.55
    {:ok, p95} = StreamingPercentile.percentile(s, "a", 0.95)
    assert close_to(p95, 9.55)
  end