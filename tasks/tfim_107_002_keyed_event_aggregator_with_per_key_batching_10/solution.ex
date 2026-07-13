  test "defaults :batch_size to exactly 100 events per key" do
    # No :batch_size given, so the documented default of 100 applies; the
    # interval is pushed far out so only the size trigger can fire.
    agg = start_agg(interval_ms: 5_000)

    Enum.each(1..99, fn n -> KeyedAggregator.push(agg, :a, n) end)

    # 99 buffered events must NOT reach the default batch size.
    refute_receive {:flushed, :a, _}, 200

    KeyedAggregator.push(agg, :a, 100)

    # The 100th event completes the batch: exactly 100 events, in push order.
    assert_receive {:flushed, :a, batch}, 1_000
    assert batch == Enum.to_list(1..100)
  end