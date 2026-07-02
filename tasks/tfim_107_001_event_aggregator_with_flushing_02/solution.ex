  test "flushes immediately when the batch reaches the configured size" do
    # Long interval so only the size trigger can fire.
    agg = start_agg(batch_size: 3, interval_ms: 5_000)

    Aggregator.push(agg, :a)
    Aggregator.push(agg, :b)
    Aggregator.push(agg, :c)

    assert_receive {:flushed, [:a, :b, :c]}, 500
  end