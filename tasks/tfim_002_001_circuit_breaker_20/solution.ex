  test "default failure_threshold of 5 trips the breaker" do
    {:ok, _pid} =
      CircuitBreaker.start_link(name: :default_thr_cb, clock: &Clock.now/0)

    for _ <- 1..4, do: CircuitBreaker.call(:default_thr_cb, error_fn())
    assert CircuitBreaker.state(:default_thr_cb) == :closed

    CircuitBreaker.call(:default_thr_cb, error_fn())
    assert CircuitBreaker.state(:default_thr_cb) == :open
  end