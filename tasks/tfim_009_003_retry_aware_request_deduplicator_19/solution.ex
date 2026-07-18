  test "GenServer is not blocked during retries", %{rd: rd} do
    slow_task =
      Task.async(fn ->
        RetryDedup.execute(rd, "slow_retry", fn -> {:error, :fail} end,
          max_retries: 5,
          base_delay_ms: 200
        )
      end)

    Process.sleep(50)

    {elapsed, result} =
      :timer.tc(fn ->
        RetryDedup.execute(rd, "fast", fn -> {:ok, :fast} end)
      end)

    assert result == {:ok, :fast}
    assert elapsed < 200_000

    Task.await(slow_task, 10_000)
  end