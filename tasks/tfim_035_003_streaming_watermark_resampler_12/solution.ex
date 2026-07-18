  test "invalid interval and options raise ArgumentError" do
    assert_raise ArgumentError, fn -> StreamingResampler.start_link(0) end
    assert_raise ArgumentError, fn -> StreamingResampler.start_link(1_000, agg: :median) end

    assert_raise ArgumentError, fn ->
      StreamingResampler.start_link(1_000, allowed_lateness: -1)
    end
  end