  test "invalidate evicts from the cache without touching the store", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v1) end)

    assert :ok = CacheLayer.invalidate(cl, :users, "u:1")
    assert Store.counts().deletes == 0

    # Evicted -> reload.
    assert {:ok, :v2} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v2) end)
    assert Store.counts().loads == 2
  end