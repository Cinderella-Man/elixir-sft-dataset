  test "cleanup only removes expired tokens, keeps active ones", %{store: store} do
    {:ok, old_id} = OneTimeTokenStore.mint(store, %{user: "old"})

    Clock.advance(900)
    {:ok, new_id} = OneTimeTokenStore.mint(store, %{user: "new"})

    Clock.advance(101)

    send(store, :cleanup)

    # Only the still-valid token survives the sweep.
    assert OneTimeTokenStore.active_count(store) == 1

    assert {:error, :not_found} = OneTimeTokenStore.verify(store, old_id)
    assert {:ok, %{user: "new"}} = OneTimeTokenStore.verify(store, new_id)
  end