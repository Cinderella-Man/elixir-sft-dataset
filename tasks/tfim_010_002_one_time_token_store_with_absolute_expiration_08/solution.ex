  test "revoke removes the token", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice"})
    assert {:ok, _} = OneTimeTokenStore.verify(store, id)

    assert :ok = OneTimeTokenStore.revoke(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, id)
  end