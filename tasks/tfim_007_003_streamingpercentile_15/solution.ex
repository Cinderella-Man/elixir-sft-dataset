  test "window_size grows with largest-ever request and never shrinks", %{sp: s} do
    # Push with window=3
    for v <- 1..5, do: StreamingPercentile.push(s, "a", v, 3)

    {:ok, w1} = StreamingPercentile.window(s, "a")
    assert length(w1) == 3

    # Push with window=10 — max_window_size grows
    for v <- 6..10, do: StreamingPercentile.push(s, "a", v, 10)

    {:ok, w2} = StreamingPercentile.window(s, "a")
    # We retained 3 then grew to 10 and pushed 5 more → length 8
    assert length(w2) == 8

    # Push with window=2 (smaller) — max_window_size does NOT shrink
    StreamingPercentile.push(s, "a", 11, 2)
    {:ok, w3} = StreamingPercentile.window(s, "a")
    # max remained 10, so length caps at 10 as we add more
    assert length(w3) == 9

    # max_window_size is internal and deliberately not inspected. Verify it
    # through the documented window/2 API instead: with the retention bound
    # still at 10, further pushes with a smaller requested window keep growing
    # the window up to exactly 10 and then cap there (it would cap at 2 if the
    # bound had shrunk).
    StreamingPercentile.push(s, "a", 12, 2)
    StreamingPercentile.push(s, "a", 13, 2)

    {:ok, w4} = StreamingPercentile.window(s, "a")
    assert length(w4) == 10

    StreamingPercentile.push(s, "a", 14, 2)

    {:ok, w5} = StreamingPercentile.window(s, "a")
    assert w5 == Enum.map(5..14, &(&1 * 1.0))
    assert Process.alive?(s)
  end