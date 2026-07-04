  test "destroy removes the session immediately", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})
    assert {:ok, _} = SessionStore.get(store, id)

    assert :ok = SessionStore.destroy(store, id)
    assert {:error, :not_found} = SessionStore.get(store, id)
  end