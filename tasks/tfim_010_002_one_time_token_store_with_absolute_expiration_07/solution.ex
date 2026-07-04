  test "verify fails after redeem", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{code: "ABC"})

    assert {:ok, _} = OneTimeTokenStore.redeem(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id)
  end