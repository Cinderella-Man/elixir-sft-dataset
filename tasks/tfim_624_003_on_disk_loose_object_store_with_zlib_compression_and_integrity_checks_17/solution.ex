  test "list_objects returns an empty list for a store with no objects", %{store: s} do
    assert ObjectStore.list_objects(s) == []

    {:ok, hash} = ObjectStore.store(s, "only one")
    assert ObjectStore.list_objects(s) == [hash]
  end