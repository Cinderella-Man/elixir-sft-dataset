  test "acquire_lease raises FunctionClauseError on out-of-contract arguments", %{lb: lb} do
    # capacity must be a positive integer
    assert_raise FunctionClauseError, fn ->
      LeaseBucket.acquire_lease(lb, "k", 0, 1.0, 1, 60_000)
    end

    # tokens must be a positive integer
    assert_raise FunctionClauseError, fn ->
      LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 0, 60_000)
    end

    # refill_rate must be a positive number
    assert_raise FunctionClauseError, fn ->
      LeaseBucket.acquire_lease(lb, "k", 5, 0.0, 1, 60_000)
    end

    # lease_timeout_ms must be a positive integer
    assert_raise FunctionClauseError, fn ->
      LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 1, 0)
    end

    # tokens must not exceed capacity
    assert_raise FunctionClauseError, fn ->
      LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 6, 60_000)
    end
  end