  test "redeem returns error for unknown token", %{store: store} do
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, "nonexistent")
  end