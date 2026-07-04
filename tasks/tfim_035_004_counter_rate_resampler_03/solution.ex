  test ":rate divides the increment by the interval in seconds" do
    result = CounterResampler.resample(@data, @interval, mode: :rate, reset: :detect)

    assert [{0, r0}, {1_000, r1}, {2_000, r2}] = result
    assert_in_delta r0, 50.0, 0.0001
    assert_in_delta r1, 150.0, 0.0001
    assert_in_delta r2, 50.0, 0.0001
  end