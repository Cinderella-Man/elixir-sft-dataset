  test "edges with fewer than two entries raise" do
    assert_raise ArgumentError, fn ->
      HistogramPercentile.start_link(
        name: :bad_edges_len,
        clock: &Clock.now/0,
        edges: [10],
        window_ms: 1000
      )
    end
  end