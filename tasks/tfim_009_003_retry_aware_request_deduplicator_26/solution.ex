  test "keeps the default 100 ms base delay when only max_retries is set", %{rd: rd} do
    {:ok, attempt_counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(attempt_counter, &(&1 + 1))
      {:error, :nope}
    end

    {elapsed_us, result} =
      :timer.tc(fn -> RetryDedup.execute(rd, "partial_delay", func, max_retries: 1) end)

    assert result == {:error, :nope}
    # initial + 1 retry = 2 total calls
    assert Agent.get(attempt_counter, & &1) == 2

    # the single retry waits min(100 * 2^0, 5000) == 100 ms
    elapsed_ms = div(elapsed_us, 1_000)
    assert elapsed_ms >= 80
    assert elapsed_ms < 2_000
  end