  test "fetch loads on a miss and caches for later hits", %{cl: cl} do
    loader = fn -> Store.loaded(:v1) end

    assert {:ok, :v1} = CacheLayer.fetch(cl, :users, "u:1", loader)
    assert {:ok, :v1} = CacheLayer.fetch(cl, :users, "u:1", loader)
    assert Store.counts().loads == 1
  end