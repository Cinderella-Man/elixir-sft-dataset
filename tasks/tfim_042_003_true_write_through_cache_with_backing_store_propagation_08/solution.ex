  test "a failed delete leaves the cached value intact", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:v1) end)
    Store.set_fail(true)

    assert {:error, :store_down} = CacheLayer.delete(cl, :users, "u:1", &Store.delete/0)
    assert Store.counts().deletes == 1

    # Still cached — no reload.
    assert {:ok, :v1} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:x) end)
    assert Store.counts().loads == 1
  end