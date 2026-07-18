  test "double-redeem is rejected", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{one_shot: true})

    assert {:ok, %{one_shot: true}} = OneTimeTokenStore.redeem(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, id)
  end