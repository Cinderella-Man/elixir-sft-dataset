  test "get returns error for unknown session id", %{store: store} do
    assert {:error, :not_found} = SessionStore.get(store, "nonexistent")
  end