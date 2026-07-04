  test "token expires after its TTL", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice"})

    Clock.advance(1_001)

    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, id)
  end