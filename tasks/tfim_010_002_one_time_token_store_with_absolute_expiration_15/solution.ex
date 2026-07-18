  test "redeeming one token does not affect another", %{store: store} do
    {:ok, id_a} = OneTimeTokenStore.mint(store, %{user: "alice"})
    {:ok, id_b} = OneTimeTokenStore.mint(store, %{user: "bob"})

    OneTimeTokenStore.redeem(store, id_a)

    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id_a)
    assert {:ok, %{user: "bob"}} = OneTimeTokenStore.verify(store, id_b)
  end