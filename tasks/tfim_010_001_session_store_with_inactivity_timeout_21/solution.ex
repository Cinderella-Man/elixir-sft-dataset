  test "cleanup only removes expired sessions, keeps active ones", %{store: store} do
    {:ok, old_id} = SessionStore.create(store, %{user: "old"})

    Clock.advance(900)
    {:ok, new_id} = SessionStore.create(store, %{user: "new"})

    # At 1001: old expired, new still has ~900ms
    Clock.advance(101)

    send(store, :cleanup)
    await_cleanup(store)

    assert {:error, :not_found} = SessionStore.get(store, old_id)
    assert {:ok, %{user: "new"}} = SessionStore.get(store, new_id)
  end