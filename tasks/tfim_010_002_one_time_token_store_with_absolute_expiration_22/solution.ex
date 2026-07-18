  test "revoke then redeem is rejected", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{code: "XYZ"})

    assert :ok = OneTimeTokenStore.revoke(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, id)
  end