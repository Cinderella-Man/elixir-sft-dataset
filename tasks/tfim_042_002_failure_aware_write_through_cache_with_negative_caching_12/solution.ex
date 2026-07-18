  test "concurrent misses call the fallback at most once" do
    cl = start_cache([])
    Tracker.set({:ok, :db_value})

    slow = fn ->
      Process.sleep(20)
      Tracker.fallback()
    end

    results =
      for _ <- 1..25 do
        Task.async(fn -> CacheLayer.fetch(cl, :users, "hot", slow) end)
      end
      |> Enum.map(&Task.await/1)

    assert Enum.all?(results, &(&1 == {:ok, :db_value}))
    assert Tracker.count() == 1
  end