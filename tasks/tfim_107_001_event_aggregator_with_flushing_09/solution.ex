  test "batch_size defaults to 100 when not provided" do
    # Long interval so only the size trigger can fire; :batch_size omitted.
    agg = start_agg(interval_ms: 5_000)

    Enum.each(1..99, fn n -> Aggregator.push(agg, n) end)

    # 99 buffered events is still one short of the documented default of 100.
    refute_receive {:flushed, _}, 200

    Aggregator.push(agg, 100)

    assert_receive {:flushed, batch}, 500
    assert batch == Enum.to_list(1..100)
  end