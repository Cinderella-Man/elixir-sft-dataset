  test "session is still alive just before timeout", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    Clock.advance(999)

    assert {:ok, %{user: "alice"}} = SessionStore.get(store, id)
  end