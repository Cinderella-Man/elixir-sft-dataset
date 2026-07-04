  test "error result is broadcast to all waiting callers", %{dd: dd} do
    func = fn ->
      Process.sleep(200)
      {:error, :something_went_wrong}
    end

    tasks =
      for _ <- 1..5 do
        Task.async(fn -> Dedup.execute(dd, "err_key", func) end)
      end

    results = Task.await_many(tasks, 5_000)

    assert Enum.all?(results, &(&1 == {:error, :something_went_wrong}))
  end