  test "put on one table does not affect another", %{cl: cl} do
    CacheLayer.put(cl, :users, "id:1", :u, &Store.write/0)
    CacheLayer.put(cl, :posts, "id:1", :p, &Store.write/0)

    assert {:ok, :u} = CacheLayer.fetch(cl, :users, "id:1", fn -> Store.loaded(:x) end)
    assert {:ok, :p} = CacheLayer.fetch(cl, :posts, "id:1", fn -> Store.loaded(:x) end)
    assert Store.counts().loads == 0
  end