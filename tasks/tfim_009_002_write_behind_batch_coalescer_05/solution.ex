  test "concurrent submitters are batched together", %{bc: bc} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    flush_fn = fn items ->
      Agent.update(counter, &(&1 + 1))
      {:ok, Enum.sum(items)}
    end

    tasks =
      for i <- 1..5 do
        Task.async(fn ->
          BatchCollector.submit(bc, :sum, i, flush_fn)
        end)
      end

    results = Task.await_many(tasks, 5_000)

    # All callers get the same result
    assert Enum.all?(results, &(&1 == {:ok, 15}))

    # flush_fn was called exactly once
    assert Agent.get(counter, & &1) == 1
  end