  test "delete removes from the store then the cache", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v1) end)

    assert :ok = CacheLayer.delete(cl, :users, "u:1", &Store.delete/0)
    assert Store.counts().deletes == 1

    # Cache miss now -> reload.
    assert {:ok, :v2} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v2) end)
    assert Store.counts().loads == 2
  end