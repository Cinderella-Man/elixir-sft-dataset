  test "window bounded to window_size — oldest values drop off", %{sp: s} do
    # Fill with 10 values at window=5 — only last 5 should remain
    for v <- 1..10, do: StreamingPercentile.push(s, "a", v, 5)

    {:ok, current} = StreamingPercentile.window(s, "a")
    assert current == [6.0, 7.0, 8.0, 9.0, 10.0]
  end