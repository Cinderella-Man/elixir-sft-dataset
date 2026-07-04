  test "unordered input is sorted internally" do
    ordered = CounterResampler.resample(@data, @interval, mode: :delta)
    shuffled = CounterResampler.resample(Enum.reverse(@data), @interval, mode: :delta)
    assert ordered == shuffled
  end