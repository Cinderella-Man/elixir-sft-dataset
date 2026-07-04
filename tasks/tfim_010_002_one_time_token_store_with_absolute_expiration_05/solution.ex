  test "redeem returns payload and removes the token", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice"})

    assert {:ok, %{user: "alice"}} = OneTimeTokenStore.redeem(store, id)
    # Second redeem fails — token is consumed
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, id)
  end