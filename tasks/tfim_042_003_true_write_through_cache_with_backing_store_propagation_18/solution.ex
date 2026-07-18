  test "put accepts an {:ok, term} writer result and caches the value", %{cl: cl} do
    writer = fn -> {:ok, :store_receipt} end

    assert {:ok, :v2} = CacheLayer.put(cl, :users, "u:1", :v2, writer)

    boom = fn -> raise "a cache hit must not call the loader" end
    assert {:ok, :v2} = CacheLayer.fetch(cl, :users, "u:1", boom)
    assert Store.counts().loads == 0
  end