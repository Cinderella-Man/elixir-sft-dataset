  test "exception in flush_fn is broadcast as {:error, {:exception, _}}", %{bc: bc} do
    tasks =
      for _ <- 1..3 do
        Task.async(fn ->
          BatchCollector.submit(bc, :raise, :item, fn _items -> raise "kaboom" end)
        end)
      end

    results = Task.await_many(tasks, 5_000)

    assert Enum.all?(results, fn
             {:error, {:exception, %RuntimeError{message: "kaboom"}}} -> true
             _ -> false
           end)
  end