  test "defaults to 3 retries with a 100 ms base delay", %{rd: rd} do
    {:ok, attempt_counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(attempt_counter, &(&1 + 1))
      {:error, :always_fails}
    end

    {elapsed_us, result} =
      :timer.tc(fn -> RetryDedup.execute(rd, "defaulted", func) end)

    assert result == {:error, :always_fails}
    # default max_retries of 3: initial + 3 retries = 4 total calls
    assert Agent.get(attempt_counter, & &1) == 4

    # default base_delay_ms of 100 gives gaps of 100 + 200 + 400 = 700 ms,
    # well under the 5000 ms default cap
    elapsed_ms = div(elapsed_us, 1_000)
    assert elapsed_ms >= 650
    assert elapsed_ms < 3_000
  end