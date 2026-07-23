  test "keeps the default max_retries when only the delay is overridden", %{rd: rd} do
    {:ok, attempt_counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(attempt_counter, &(&1 + 1))
      {:error, :always_fails}
    end

    assert {:error, :always_fails} =
             RetryDedup.execute(rd, "partial_retries", func, base_delay_ms: 5)

    # :max_retries still defaults to 3: initial + 3 retries = 4 total calls
    assert Agent.get(attempt_counter, & &1) == 4
  end