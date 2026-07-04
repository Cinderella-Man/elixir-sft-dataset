  test ":raw reset mode allows negative increments on a decrease" do
    result = CounterResampler.resample(@data, @interval, mode: :delta, reset: :raw)

    # last pair 300 -> 50 is -250, attributed to bucket 2000
    assert result == [{0, 50}, {1_000, 150}, {2_000, -250}]
  end