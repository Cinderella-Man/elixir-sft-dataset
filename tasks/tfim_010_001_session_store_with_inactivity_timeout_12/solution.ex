  test "touch returns error for unknown session", %{store: store} do
    assert {:error, :not_found} = SessionStore.touch(store, "nonexistent")
  end