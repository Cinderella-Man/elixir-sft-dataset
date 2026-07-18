  test "invalidate_all clears every key in the table", %{cl: cl} do
    for i <- 1..5 do
      CacheLayer.fetch(cl, :users, "u:#{i}", &Tracker.fallback/0)
    end

    assert Tracker.count() == 5
    :ok = CacheLayer.invalidate_all(cl, :users)

    for i <- 1..5 do
      CacheLayer.fetch(cl, :users, "u:#{i}", &Tracker.fallback/0)
    end

    assert Tracker.count() == 10
  end