  test "the default byte budget is 1_048_576" do
    agg = start_agg(interval_ms: 5_000)

    big = :binary.copy("a", 1_048_575)

    # One byte under the default budget: strictly below, so no flush.
    WeightedAggregator.push(agg, big)
    refute_receive {:flushed, _}, 100

    # 1_048_575 + 1 = 1_048_576 >= the default budget -> flush.
    WeightedAggregator.push(agg, "b")
    assert_receive {:flushed, [^big, "b"]}, 500
  end