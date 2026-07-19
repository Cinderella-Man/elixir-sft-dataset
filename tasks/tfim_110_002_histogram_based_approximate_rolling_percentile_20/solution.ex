  test "non-positive window_ms raises synchronously from start_link" do
    assert_raise ArgumentError, fn ->
      HistogramPercentile.start_link(
        name: :bad_window,
        clock: &Clock.now/0,
        edges: [0, 10, 20],
        window_ms: 0
      )
    end
  end