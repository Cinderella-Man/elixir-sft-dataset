  test "revoke returns :ok for unknown token", %{store: store} do
    assert :ok = OneTimeTokenStore.revoke(store, "nonexistent")
  end