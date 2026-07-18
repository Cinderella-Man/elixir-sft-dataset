  test ":rate scales by a sub-second interval length" do
    # interval 500ms = 0.5s, so an increment of +50 becomes 100.0 per second.
    data = [{0, 100}, {200, 150}, {700, 200}]
    result = CounterResampler.resample(data, 500, mode: :rate, fill: :zero)

    assert [{0, r0}, {500, r1}] = result
    assert_in_delta r0, 100.0, 0.0001
    assert_in_delta r1, 100.0, 0.0001
  end