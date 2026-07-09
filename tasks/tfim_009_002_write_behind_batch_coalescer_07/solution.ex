  test "batch flushes immediately when max_batch_size is reached", %{bc: bc} do
    {elapsed, results} =
      :timer.tc(fn ->
        tasks =
          for i <- 1..3 do
            Task.async(fn ->
              BatchCollector.submit(bc, :fast, i, fn items -> {:ok, items} end, max_batch_size: 3)
            end)
          end

        Task.await_many(tasks, 5_000)
      end)

    # Should flush well before the 500ms timer
    assert elapsed < 300_000

    assert Enum.all?(results, fn {:ok, items} -> length(items) == 3 end)
  end