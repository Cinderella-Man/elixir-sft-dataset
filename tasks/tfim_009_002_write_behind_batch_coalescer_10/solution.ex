  test "error result is broadcast to all callers in the batch", %{bc: bc} do
    tasks =
      for _ <- 1..5 do
        Task.async(fn ->
          BatchCollector.submit(bc, :err, :item, fn _items -> {:error, :fail} end)
        end)
      end

    results = Task.await_many(tasks, 5_000)
    assert Enum.all?(results, &(&1 == {:error, :fail}))
  end