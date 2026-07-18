  test "mixed concurrent calls on several keys", %{dd: dd} do
    {:ok, counters} = Agent.start_link(fn -> %{} end)

    tasks =
      for key <- ["a", "b", "c"], _ <- 1..10 do
        Task.async(fn ->
          Dedup.execute(dd, key, fn ->
            Agent.update(counters, fn map ->
              Map.update(map, key, 1, &(&1 + 1))
            end)

            Process.sleep(150)
            {:ok, key}
          end)
        end)
      end

    results = Task.await_many(tasks, 10_000)

    # All callers for each key should get the same result
    for key <- ["a", "b", "c"] do
      key_results = Enum.filter(results, &(&1 == {:ok, key}))
      assert length(key_results) == 10
    end

    # Each key's function was called exactly once
    counts = Agent.get(counters, & &1)
    assert counts["a"] == 1
    assert counts["b"] == 1
    assert counts["c"] == 1
  end