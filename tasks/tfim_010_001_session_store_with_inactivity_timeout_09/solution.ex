  test "session expires after inactivity timeout", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    Clock.advance(1_001)

    assert {:error, :not_found} = SessionStore.get(store, id)
  end