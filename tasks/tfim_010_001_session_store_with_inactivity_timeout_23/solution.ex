  test "create works with various data types", %{store: store} do
    {:ok, id1} = SessionStore.create(store, "just a string")
    {:ok, id2} = SessionStore.create(store, [1, 2, 3])
    {:ok, id3} = SessionStore.create(store, {:tuple, :data})

    assert {:ok, "just a string"} = SessionStore.get(store, id1)
    assert {:ok, [1, 2, 3]} = SessionStore.get(store, id2)
    assert {:ok, {:tuple, :data}} = SessionStore.get(store, id3)
  end