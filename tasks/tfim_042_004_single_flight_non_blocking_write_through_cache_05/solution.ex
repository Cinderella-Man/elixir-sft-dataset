  test "concurrent misses of the same key run the fallback exactly once", %{cl: cl} do
    fun = fn ->
      Process.sleep(40)
      Tracker.fallback()
    end

    results =
      for _ <- 1..30 do
        Task.async(fn -> CacheLayer.fetch(cl, :users, "hot", fun) end)
      end
      |> Enum.map(&Task.await/1)

    assert Enum.all?(results, &(&1 == {:ok, :db_value}))
    assert Tracker.count() == 1
  end