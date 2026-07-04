  test "open state: calls return :circuit_open without executing the function" do
    # Trip the breaker
    for _ <- 1..3, do: CircuitBreaker.call(:test_cb, error_fn())
    assert CircuitBreaker.state(:test_cb) == :open

    # Track whether the function gets called
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    assert {:error, :circuit_open} = CircuitBreaker.call(:test_cb, counting_fn(counter))
    # function was never called
    assert Agent.get(counter, & &1) == 0
  end