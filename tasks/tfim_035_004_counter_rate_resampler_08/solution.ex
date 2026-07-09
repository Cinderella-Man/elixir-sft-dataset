  test "the first bucket has no measured increase" do
    # single sample: one bucket, filled value (no predecessor)
    result = CounterResampler.resample([{300, 100}], @interval, mode: :delta, fill: :zero)
    assert result == [{0, 0}]

    nil_result = CounterResampler.resample([{300, 100}], @interval, mode: :delta, fill: nil)
    assert nil_result == [{0, nil}]
  end