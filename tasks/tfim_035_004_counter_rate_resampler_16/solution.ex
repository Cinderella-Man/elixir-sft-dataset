  test "negative timestamps floor down to their bucket boundary" do
    # floor(-1500/1000) = -2 -> -2000, floor(-300/1000) = -1 -> -1000,
    # floor(200/1000) = 0 -> 0.  Increment +30 lands in bucket -1000 (later
    # sample t=-300), increment +50 lands in bucket 0 (later sample t=200).
    data = [{-1_500, 10}, {-300, 40}, {200, 90}]
    result = CounterResampler.resample(data, 1_000, mode: :delta, fill: :zero)

    assert result == [{-2_000, 0}, {-1_000, 30}, {0, 50}]
  end