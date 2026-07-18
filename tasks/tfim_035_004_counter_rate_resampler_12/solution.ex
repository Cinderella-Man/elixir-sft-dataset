  test "output covers every bucket between first and last, sorted" do
    data = [{0, 0}, {4_200, 100}]
    result = CounterResampler.resample(data, @interval, mode: :delta, fill: :zero)
    buckets = Enum.map(result, fn {b, _} -> b end)

    assert buckets == [0, 1_000, 2_000, 3_000, 4_000]
    assert buckets == Enum.sort(buckets)
  end