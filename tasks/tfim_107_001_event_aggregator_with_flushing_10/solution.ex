  test "interval_ms defaults to 1_000 when not provided" do
    # Batch size large enough that only the time trigger can fire.
    agg = start_agg(batch_size: 50)

    Aggregator.push(agg, :a)

    # A default of 1_000ms means no flush is due yet at ~700ms.
    refute_receive {:flushed, _}, 700

    # But the partial batch must be flushed once the default interval elapses.
    assert_receive {:flushed, [:a]}, 800
  end