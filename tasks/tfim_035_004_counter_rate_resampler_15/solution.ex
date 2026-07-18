  test "argument validation happens even when the data list is empty" do
    assert_raise ArgumentError, fn ->
      CounterResampler.resample([], 0, mode: :delta)
    end

    assert_raise ArgumentError, fn ->
      CounterResampler.resample([], 1_000, mode: :average)
    end

    assert_raise ArgumentError, fn ->
      CounterResampler.resample([], 1_000, reset: :ignore)
    end
  end