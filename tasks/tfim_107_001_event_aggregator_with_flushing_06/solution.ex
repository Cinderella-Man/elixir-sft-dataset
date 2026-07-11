  test "does not flush empty batches on the interval" do
    start_agg(batch_size: 5, interval_ms: 150)

    # No pushes at all — the callback must never be invoked, even across
    # multiple interval periods.
    refute_receive {:flushed, _}, 400
  end