  test "sessions are fully independent", %{store: store} do
    {:ok, id_a} = SessionStore.create(store, %{user: "alice"})

    Clock.advance(500)
    {:ok, id_b} = SessionStore.create(store, %{user: "bob"})

    # At time 1001: alice expires, bob still has ~500ms left
    Clock.advance(501)

    assert {:error, :not_found} = SessionStore.get(store, id_a)
    assert {:ok, %{user: "bob"}} = SessionStore.get(store, id_b)
  end