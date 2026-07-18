  test "empty buckets fill with nil in :rate mode when requested" do
    data = [{0, 100}, {300, 150}, {2_300, 400}]
    result = CounterResampler.resample(data, 1_000, mode: :rate, fill: nil)

    assert [{0, r0}, {1_000, gap}, {2_000, r2}] = result
    assert gap == nil
    assert_in_delta r0, 50.0, 0.0001
    assert_in_delta r2, 250.0, 0.0001
  end