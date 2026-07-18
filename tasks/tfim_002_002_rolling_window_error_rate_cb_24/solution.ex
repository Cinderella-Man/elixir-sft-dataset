  test "start_link raises when the required name option is absent" do
    assert_raise KeyError, fn ->
      RollingRateCircuitBreaker.start_link(window_size: 5, clock: &Clock.now/0)
    end
  end