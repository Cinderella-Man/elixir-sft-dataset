  test "empty buckets fill with nil when requested" do
    data = [{0, 100}, {300, 150}, {2_300, 400}]
    result = CounterResampler.resample(data, @interval, mode: :delta, fill: nil)

    assert result == [{0, 50}, {1_000, nil}, {2_000, 250}]
  end