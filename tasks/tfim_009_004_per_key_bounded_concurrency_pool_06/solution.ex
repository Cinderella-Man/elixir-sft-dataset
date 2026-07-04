  test "each caller gets its own result", %{kp: kp} do
    tasks =
      for i <- 1..5 do
        Task.async(fn ->
          KeyedPool.execute(kp, :k, fn ->
            {:ok, i}
          end)
        end)
      end

    results = Task.await_many(tasks, 5_000)

    # Each caller should get a distinct result matching their own i
    values = Enum.map(results, fn {:ok, v} -> v end) |> Enum.sort()
    assert values == [1, 2, 3, 4, 5]
  end