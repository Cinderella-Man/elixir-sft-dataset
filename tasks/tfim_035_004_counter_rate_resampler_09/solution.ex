  test "all samples in one bucket sum their increments" do
    data = [{100, 10}, {200, 25}, {300, 40}]
    result = CounterResampler.resample(data, @interval, mode: :delta)

    # increments +15 and +15 both land in bucket 0
    assert result == [{0, 30}]
  end