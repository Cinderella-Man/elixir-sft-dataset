  test "get retrieves created session data", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice", role: :admin})

    assert {:ok, %{user: "alice", role: :admin}} = SessionStore.get(store, id)
  end