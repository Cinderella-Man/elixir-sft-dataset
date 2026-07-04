  test ":delta sums per-bucket increments with reset detection" do
    result = CounterResampler.resample(@data, @interval, mode: :delta, reset: :detect)

    assert result == [{0, 50}, {1_000, 150}, {2_000, 50}]
  end