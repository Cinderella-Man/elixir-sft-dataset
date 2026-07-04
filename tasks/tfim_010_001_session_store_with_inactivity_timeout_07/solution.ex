  test "update replaces session data", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice", count: 0})

    assert {:ok, %{user: "alice", count: 42}} =
             SessionStore.update(store, id, %{user: "alice", count: 42})

    assert {:ok, %{user: "alice", count: 42}} = SessionStore.get(store, id)
  end