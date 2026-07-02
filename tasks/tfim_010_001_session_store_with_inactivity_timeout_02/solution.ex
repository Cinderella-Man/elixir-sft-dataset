  test "create returns a unique session id", %{store: store} do
    assert {:ok, id1} = SessionStore.create(store, %{user: "alice"})
    assert {:ok, id2} = SessionStore.create(store, %{user: "bob"})

    assert is_binary(id1)
    assert is_binary(id2)
    assert id1 != id2
  end