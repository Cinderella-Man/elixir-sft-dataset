  test "queued callers are started as slots free up" do
    {:ok, kp} = KeyedPool.start_link(max_concurrency: 1)
    {:ok, order} = Agent.start_link(fn -> [] end)

    tasks =
      for i <- 1..4 do
        Task.async(fn ->
          KeyedPool.execute(kp, :serial, fn ->
            Agent.update(order, fn list -> list ++ [i] end)
            Process.sleep(50)
            {:ok, i}
          end)
        end)
      end

    # Give them a moment to all register
    Process.sleep(20)

    results = Task.await_many(tasks, 10_000)

    # All should complete
    values = Enum.map(results, fn {:ok, v} -> v end) |> Enum.sort()
    assert values == [1, 2, 3, 4]

    # With max_concurrency: 1, execution is serial — order should be FIFO
    execution_order = Agent.get(order, & &1)
    assert execution_order == Enum.sort(execution_order)
  end