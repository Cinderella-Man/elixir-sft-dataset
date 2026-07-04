  test "a failed write leaves the previously cached value intact", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v1) end)
    Store.set_fail(true)

    assert {:error, :store_down} = CacheLayer.put(cl, :users, "u:1", :v2, &Store.write/0)
    assert Store.counts().writes == 1

    # Cache untouched — still the old value, no reload.
    assert {:ok, :v1} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:x) end)
    assert Store.counts().loads == 1
  end