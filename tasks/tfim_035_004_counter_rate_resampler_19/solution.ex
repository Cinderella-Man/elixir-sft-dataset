  test "an undocumented :fill value raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      CounterResampler.resample([{0, 100}, {300, 150}], 1_000, fill: :empty)
    end
  end