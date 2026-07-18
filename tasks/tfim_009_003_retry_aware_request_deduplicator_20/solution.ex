  test "all callers receive the final error after retries exhausted", %{rd: rd} do
    func = fn ->
      Process.sleep(50)
      {:error, :persistent_failure}
    end

    tasks =
      for _ <- 1..5 do
        Task.async(fn ->
          RetryDedup.execute(rd, "err_broadcast", func,
            max_retries: 1,
            base_delay_ms: 10
          )
        end)
      end

    results = Task.await_many(tasks, 5_000)
    assert Enum.all?(results, &(&1 == {:error, :persistent_failure}))
  end