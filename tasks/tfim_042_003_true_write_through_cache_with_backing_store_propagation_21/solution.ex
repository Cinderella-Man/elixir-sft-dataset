  test "invalidate_all clears only the named table and leaves other tables cached", %{cl: cl} do
    CacheLayer.fetch(cl, :users, "id:1", fn -> Store.loaded(:u) end)
    CacheLayer.fetch(cl, :posts, "id:1", fn -> Store.loaded(:p) end)

    assert :ok = CacheLayer.invalidate_all(cl, :users)

    boom = fn -> raise "a cache hit must not call the loader" end
    assert {:ok, :p} = CacheLayer.fetch(cl, :posts, "id:1", boom)
    assert {:ok, :u2} = CacheLayer.fetch(cl, :users, "id:1", fn -> Store.loaded(:u2) end)
    assert Store.counts().loads == 3
  end