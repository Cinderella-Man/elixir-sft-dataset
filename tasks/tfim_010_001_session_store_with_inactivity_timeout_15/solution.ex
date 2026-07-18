  test "update resets the inactivity timer", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    Clock.advance(800)
    assert {:ok, _} = SessionStore.update(store, id, %{user: "alice", visits: 1})

    # 800ms since update — should still be alive
    Clock.advance(800)
    assert {:ok, %{user: "alice", visits: 1}} = SessionStore.get(store, id)
  end