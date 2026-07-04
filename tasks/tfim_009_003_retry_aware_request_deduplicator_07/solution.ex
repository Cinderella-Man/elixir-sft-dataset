  test "retries on failure and eventually succeeds", %{rd: rd} do
    {:ok, attempt_counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      n = Agent.get_and_update(attempt_counter, fn n -> {n, n + 1} end)

      if n < 2 do
        {:error, :not_yet}
      else
        {:ok, :finally}
      end
    end

    result =
      RetryDedup.execute(rd, "flaky", func,
        max_retries: 5,
        base_delay_ms: 10
      )

    assert result == {:ok, :finally}
    # initial + 2 retries = 3 total calls
    assert Agent.get(attempt_counter, & &1) == 3
  end