  test "invalid interval and options raise ArgumentError" do
    assert_raise ArgumentError, fn ->
      CounterResampler.resample(@data, 0, mode: :delta)
    end

    assert_raise ArgumentError, fn ->
      CounterResampler.resample(@data, @interval, mode: :average)
    end

    assert_raise ArgumentError, fn ->
      CounterResampler.resample(@data, @interval, reset: :ignore)
    end
  end