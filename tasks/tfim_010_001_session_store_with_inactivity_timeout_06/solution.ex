  test "destroy returns :ok even for unknown session", %{store: store} do
    assert :ok = SessionStore.destroy(store, "nonexistent")
  end