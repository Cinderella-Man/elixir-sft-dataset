  test "put writes through to the store then updates the cache", %{cl: cl} do
    assert {:ok, :new} = CacheLayer.put(cl, :users, "u:1", :new, &Store.write/0)
    assert Store.counts().writes == 1

    # Subsequent fetch is served from cache — loader never runs.
    assert {:ok, :new} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:from_db) end)
    assert Store.counts().loads == 0
  end