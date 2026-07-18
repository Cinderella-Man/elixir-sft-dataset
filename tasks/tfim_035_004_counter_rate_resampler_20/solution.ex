  test "a non-integer or negative interval raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      CounterResampler.resample([{0, 100}, {300, 150}], 1_000.0, mode: :delta)
    end

    assert_raise ArgumentError, fn ->
      CounterResampler.resample([{0, 100}, {300, 150}], -1_000, mode: :delta)
    end
  end