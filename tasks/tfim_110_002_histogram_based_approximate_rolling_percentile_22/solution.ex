  test "non-positive slots raises synchronously from start_link" do
    assert_raise ArgumentError, fn ->
      HistogramPercentile.start_link(
        name: :bad_slots,
        clock: &Clock.now/0,
        edges: [0, 10, 20],
        window_ms: 1000,
        slots: 0
      )
    end
  end