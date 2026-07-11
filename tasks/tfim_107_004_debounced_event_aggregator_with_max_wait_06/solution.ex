  test "never flushes an empty batch" do
    start_agg(idle_ms: 100, max_wait_ms: 100, batch_size: 3)

    refute_receive {:flushed, _}, 400
  end