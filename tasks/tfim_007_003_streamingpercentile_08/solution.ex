  test "median of odd-length sorted stream is the middle element", %{sp: s} do
    for v <- [10, 20, 30, 40, 50], do: StreamingPercentile.push(s, "a", v, 5)

    {:ok, med} = StreamingPercentile.percentile(s, "a", 0.5)
    assert med == 30.0
  end