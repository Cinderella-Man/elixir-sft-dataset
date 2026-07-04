  test "concurrent calls with the same key share execution", %{rd: rd} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(counter, &(&1 + 1))
      Process.sleep(200)
      {:ok, :result}
    end

    tasks =
      for _ <- 1..10 do
        Task.async(fn -> RetryDedup.execute(rd, "same", func) end)
      end

    results = Task.await_many(tasks, 5_000)

    assert Enum.all?(results, &(&1 == {:ok, :result}))
    assert Agent.get(counter, & &1) == 1
  end