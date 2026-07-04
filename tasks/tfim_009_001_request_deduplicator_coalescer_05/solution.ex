  test "concurrent calls with the same key execute the function exactly once", %{dd: dd} do
    # A counter to track how many times the function actually runs
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    # The function sleeps a bit so concurrent callers pile up
    func = fn ->
      Agent.update(counter, &(&1 + 1))
      Process.sleep(200)
      {:ok, :result}
    end

    tasks =
      for _ <- 1..10 do
        Task.async(fn -> Dedup.execute(dd, "same_key", func) end)
      end

    results = Task.await_many(tasks, 5_000)

    # All 10 callers got the same result
    assert Enum.all?(results, &(&1 == {:ok, :result}))

    # The function was called exactly once
    assert Agent.get(counter, & &1) == 1
  end