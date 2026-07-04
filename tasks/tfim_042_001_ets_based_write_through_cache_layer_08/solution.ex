  test "invalidate_all clears every key in the table", %{cl: cl} do
    for i <- 1..5 do
      CacheLayer.fetch(cl, :users, "u:#{i}", &CallTracker.fallback/0)
    end

    assert CallTracker.call_count() == 5

    :ok = CacheLayer.invalidate_all(cl, :users)

    for i <- 1..5 do
      CacheLayer.fetch(cl, :users, "u:#{i}", &CallTracker.fallback/0)
    end

    assert CallTracker.call_count() == 10
  end