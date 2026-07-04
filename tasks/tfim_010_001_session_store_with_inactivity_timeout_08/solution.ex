  test "update returns error for unknown session", %{store: store} do
    assert {:error, :not_found} = SessionStore.update(store, "nonexistent", %{})
  end