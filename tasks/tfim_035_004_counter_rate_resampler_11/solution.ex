  test "empty input returns empty list" do
    assert CounterResampler.resample([], @interval, mode: :delta) == []
  end