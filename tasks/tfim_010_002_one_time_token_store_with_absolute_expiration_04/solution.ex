  test "verify returns error for unknown token", %{store: store} do
    assert {:error, :not_found} = OneTimeTokenStore.verify(store, "nonexistent")
  end