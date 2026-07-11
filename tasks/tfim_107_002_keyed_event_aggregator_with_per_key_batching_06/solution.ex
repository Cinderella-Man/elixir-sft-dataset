  test "does not flush empty keys on the interval" do
    start_agg(batch_size: 5, interval_ms: 150)

    refute_receive {:flushed, _, _}, 400
  end