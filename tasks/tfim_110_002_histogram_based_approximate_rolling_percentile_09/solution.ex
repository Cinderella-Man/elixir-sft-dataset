  test "invalid edges raise" do
    assert_raise ArgumentError, fn ->
      HistogramPercentile.start_link(
        name: :bad1,
        clock: &Clock.now/0,
        edges: [10, 5],
        window_ms: 1000
      )
    end
  end