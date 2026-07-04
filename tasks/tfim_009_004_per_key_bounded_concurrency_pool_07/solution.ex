  test "every caller's function is executed", %{kp: kp} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    tasks =
      for _ <- 1..5 do
        Task.async(fn ->
          KeyedPool.execute(kp, :k, fn ->
            Agent.update(counter, &(&1 + 1))
            Process.sleep(50)
            {:ok, :done}
          end)
        end)
      end

    Task.await_many(tasks, 10_000)

    # All 5 functions ran (unlike dedup which would only run 1)
    assert Agent.get(counter, & &1) == 5
  end