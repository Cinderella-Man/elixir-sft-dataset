  test "median of even-length stream linearly interpolates", %{sp: s} do
    for v <- [10, 20, 30, 40], do: StreamingPercentile.push(s, "a", v, 4)

    # sorted = [10, 20, 30, 40], N=4, rank = 0.5 * 3 = 1.5
    # lo=1, hi=2, frac=0.5, result = 20 + 0.5*(30-20) = 25
    {:ok, med} = StreamingPercentile.percentile(s, "a", 0.5)
    assert close_to(med, 25.0)
  end