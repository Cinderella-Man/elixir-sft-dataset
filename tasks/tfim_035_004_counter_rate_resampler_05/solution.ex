  test "empty buckets fill with zero in :delta mode" do
    data = [{0, 100}, {300, 150}, {2_300, 400}]
    result = CounterResampler.resample(data, @interval, mode: :delta, fill: :zero)

    assert result == [{0, 50}, {1_000, 0}, {2_000, 250}]
  end