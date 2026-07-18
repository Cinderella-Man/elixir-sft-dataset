  test "tokens are fully independent", %{store: store} do
    {:ok, id_a} = OneTimeTokenStore.mint(store, %{user: "alice"})

    Clock.advance(500)
    {:ok, id_b} = OneTimeTokenStore.mint(store, %{user: "bob"})

    # At time 1001: alice expired, bob still has ~500ms
    Clock.advance(501)

    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id_a)
    assert {:ok, %{user: "bob"}} = OneTimeTokenStore.verify(store, id_b)
  end