  test "returns last error when all retries exhausted", %{rd: rd} do
    {:ok, attempt_counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(attempt_counter, &(&1 + 1))
      {:error, :always_fails}
    end

    result =
      RetryDedup.execute(rd, "doomed", func,
        max_retries: 3,
        base_delay_ms: 10
      )

    assert result == {:error, :always_fails}
    # initial + 3 retries = 4 total calls
    assert Agent.get(attempt_counter, & &1) == 4
  end