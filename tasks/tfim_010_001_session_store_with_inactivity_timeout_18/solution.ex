  test "destroying one session does not affect another", %{store: store} do
    {:ok, id_a} = SessionStore.create(store, %{user: "alice"})
    {:ok, id_b} = SessionStore.create(store, %{user: "bob"})

    SessionStore.destroy(store, id_a)

    assert {:error, :not_found} = SessionStore.get(store, id_a)
    assert {:ok, %{user: "bob"}} = SessionStore.get(store, id_b)
  end