  test "invalidating a non-existent key returns :ok without error", %{cl: cl} do
    assert :ok = CacheLayer.invalidate(cl, :users, "no-such-key")
  end