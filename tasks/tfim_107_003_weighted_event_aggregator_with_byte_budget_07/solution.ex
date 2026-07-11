  test "does not flush empty batches on the interval" do
    start_agg(max_bytes: 10, interval_ms: 150, size_fn: fn n -> n end)

    refute_receive {:flushed, _}, 400
  end