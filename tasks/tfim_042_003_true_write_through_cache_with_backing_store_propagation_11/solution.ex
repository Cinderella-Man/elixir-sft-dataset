  test "invalidate on a non-existent key returns :ok", %{cl: cl} do
    assert :ok = CacheLayer.invalidate(cl, :users, "nope")
  end