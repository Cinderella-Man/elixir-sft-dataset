  test "invalidate_all clears the table without touching the store", %{cl: cl} do
    for i <- 1..5 do
      CacheLayer.fetch(cl, :users, "u:#{i}", fn -> Store.loaded(i) end)
    end

    assert Store.counts().loads == 5
    assert :ok = CacheLayer.invalidate_all(cl, :users)
    assert Store.counts().deletes == 0

    for i <- 1..5 do
      CacheLayer.fetch(cl, :users, "u:#{i}", fn -> Store.loaded(i) end)
    end

    assert Store.counts().loads == 10
  end