  test "retries on exception and wraps as {:error, {:exception, _}}", %{rd: rd} do
    {:ok, attempt_counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(attempt_counter, &(&1 + 1))
      raise "kaboom"
    end

    result =
      RetryDedup.execute(rd, "raises", func,
        max_retries: 2,
        base_delay_ms: 10
      )

    assert {:error, {:exception, %RuntimeError{message: "kaboom"}}} = result
    # initial + 2 retries = 3 total calls
    assert Agent.get(attempt_counter, & &1) == 3
  end