  test "a cache registered under :name serves fetches and hits through that name" do
    pid = start_supervised!({CacheLayer, [name: :named_cache_layer]}, id: :named_cache)
    assert Process.whereis(:named_cache_layer) == pid

    assert {:ok, :db_value} =
             CacheLayer.fetch(:named_cache_layer, :users, "u:1", &Tracker.fallback/0)

    assert Tracker.count() == 1

    # A hit must be locatable via the registered name alone, with no recompute.
    boom = fn -> raise "fallback must not run on a cache hit" end
    assert {:ok, :db_value} = CacheLayer.fetch(:named_cache_layer, :users, "u:1", boom)
    assert Tracker.count() == 1

    assert :ok = CacheLayer.invalidate(:named_cache_layer, :users, "u:1")

    assert {:ok, :db_value} =
             CacheLayer.fetch(:named_cache_layer, :users, "u:1", &Tracker.fallback/0)

    assert Tracker.count() == 2
  end