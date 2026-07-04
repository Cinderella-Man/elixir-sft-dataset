  test "empty buckets fill with 0.0 in :rate mode under :zero" do
    data = [{0, 100}, {300, 150}, {2_300, 400}]
    result = CounterResampler.resample(data, @interval, mode: :rate, fill: :zero)

    assert [{0, _}, {1_000, gap}, {2_000, _}] = result
    assert gap === 0.0
  end