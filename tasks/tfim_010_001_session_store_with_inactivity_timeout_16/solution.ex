  test "update returns error for expired session", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    Clock.advance(1_001)

    assert {:error, :not_found} = SessionStore.update(store, id, %{user: "alice"})
  end