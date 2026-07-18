  test "a failed put does not populate the cache for a previously uncached key", %{cl: cl} do
    Store.set_fail(true)

    assert {:error, :store_down} = CacheLayer.put(cl, :users, "u:9", :v2, &Store.write/0)

    Store.set_fail(false)

    assert {:ok, :from_store} =
             CacheLayer.fetch(cl, :users, "u:9", fn -> Store.loaded(:from_store) end)

    assert Store.counts().loads == 1
    assert Store.counts().writes == 1
  end