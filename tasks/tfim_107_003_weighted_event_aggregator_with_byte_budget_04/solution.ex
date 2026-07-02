  test "the default size_fn measures binary byte size" do
    agg = start_agg(max_bytes: 5, interval_ms: 5_000)

    WeightedAggregator.push(agg, "abc")
    refute_receive {:flushed, _}, 80

    WeightedAggregator.push(agg, "de")
    # 3 + 2 = 5 >= 5 -> flush.
    assert_receive {:flushed, ["abc", "de"]}, 500
  end