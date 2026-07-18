  test "error result frees the slot", %{kp: kp} do
    {:ok, order} = Agent.start_link(fn -> [] end)

    # Fill both slots with errors, then queue successes
    tasks =
      for i <- 1..4 do
        Task.async(fn ->
          KeyedPool.execute(kp, :mixed, fn ->
            Agent.update(order, fn list -> list ++ [i] end)

            if i <= 2 do
              Process.sleep(100)
              {:error, :fail}
            else
              {:ok, :success}
            end
          end)
        end)
      end

    results = Task.await_many(tasks, 10_000)

    errors = Enum.count(results, &match?({:error, _}, &1))
    oks = Enum.count(results, &match?({:ok, _}, &1))
    assert errors == 2
    assert oks == 2
  end