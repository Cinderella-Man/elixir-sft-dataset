  test "exception in func is broadcast as {:error, {:exception, _}}", %{dd: dd} do
    func = fn ->
      Process.sleep(100)
      raise "kaboom"
    end

    tasks =
      for _ <- 1..5 do
        Task.async(fn -> Dedup.execute(dd, "raise_key", func) end)
      end

    results = Task.await_many(tasks, 5_000)

    assert Enum.all?(results, fn
             {:error, {:exception, %RuntimeError{message: "kaboom"}}} -> true
             _ -> false
           end)
  end