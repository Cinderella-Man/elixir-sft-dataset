  test "callers arriving during retry share the eventual result", %{rd: rd} do
    {:ok, attempt_counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      n = Agent.get_and_update(attempt_counter, fn n -> {n, n + 1} end)

      if n < 2 do
        {:error, :not_yet}
      else
        Process.sleep(100)
        {:ok, :shared_result}
      end
    end

    # First caller triggers execution
    task1 =
      Task.async(fn ->
        RetryDedup.execute(rd, "join", func,
          max_retries: 5,
          base_delay_ms: 50
        )
      end)

    # Wait for first attempt + some retry delay, then add a second caller
    Process.sleep(120)

    task2 =
      Task.async(fn ->
        RetryDedup.execute(rd, "join", func,
          max_retries: 5,
          base_delay_ms: 50
        )
      end)

    [r1, r2] = Task.await_many([task1, task2], 10_000)

    # Both get the same result
    assert r1 == {:ok, :shared_result}
    assert r2 == {:ok, :shared_result}
  end