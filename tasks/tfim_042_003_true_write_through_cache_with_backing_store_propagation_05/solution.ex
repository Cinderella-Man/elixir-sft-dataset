  test "put overwrites an existing cached value", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:old) end)
    assert {:ok, :updated} = CacheLayer.put(cl, :users, "u:1", :updated, &Store.write/0)

    assert {:ok, :updated} = CacheLayer.fetch(cl, :users, "u:1", fn -> Store.loaded(:x) end)
    # Only the original load happened; the second fetch was a cache hit.
    assert Store.counts().loads == 1
  end