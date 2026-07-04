  test "token is still alive just before TTL", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice"})

    Clock.advance(999)

    assert {:ok, %{user: "alice"}} = OneTimeTokenStore.verify(store, id)
  end