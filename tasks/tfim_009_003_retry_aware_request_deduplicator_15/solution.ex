  test "status reflects retry state", %{rd: rd} do
    {:ok, attempt_counter} = Agent.start_link(fn -> 0 end)

    task =
      Task.async(fn ->
        RetryDedup.execute(
          rd,
          "retrying",
          fn ->
            n = Agent.get_and_update(attempt_counter, fn n -> {n, n + 1} end)

            if n < 3 do
              {:error, :not_yet}
            else
              Process.sleep(100)
              {:ok, :done}
            end
          end,
          max_retries: 5,
          base_delay_ms: 100
        )
      end)

    # Wait for first failure + start of retry delay
    Process.sleep(150)
    status = RetryDedup.status(rd, "retrying")
    assert match?({:retrying, _, 5}, status)

    Task.await(task, 10_000)

    # After completion, status is idle
    assert RetryDedup.status(rd, "retrying") == :idle
  end