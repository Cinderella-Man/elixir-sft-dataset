  test "invalidate_all leaves entries cached in other tables intact", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "id:1", &Tracker.fallback/0)
    CacheLayer.fetch(cl, :posts, "id:1", &Tracker.fallback/0)
    assert Tracker.count() == 2

    assert :ok = CacheLayer.invalidate_all(cl, :users)

    boom = fn -> raise ":posts must survive invalidate_all(:users)" end
    assert {:ok, :db_value} = CacheLayer.fetch(cl, :posts, "id:1", boom)
    assert Tracker.count() == 2

    CacheLayer.fetch(cl, :users, "id:1", &Tracker.fallback/0)
    assert Tracker.count() == 3
  end