  test "different keys execute independently and concurrently", %{dd: dd} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(counter, &(&1 + 1))
      Process.sleep(100)
      {:ok, :done}
    end

    tasks =
      for i <- 1..5 do
        Task.async(fn -> Dedup.execute(dd, "key:#{i}", func) end)
      end

    results = Task.await_many(tasks, 5_000)

    assert Enum.all?(results, &(&1 == {:ok, :done}))
    # Each distinct key triggers its own execution
    assert Agent.get(counter, & &1) == 5
  end