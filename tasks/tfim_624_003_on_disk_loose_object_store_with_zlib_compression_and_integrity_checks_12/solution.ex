  test "list_objects returns all hashes sorted", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "one")
    {:ok, h2} = ObjectStore.store(s, "two")
    {:ok, h3} = ObjectStore.store(s, "three")
    assert ObjectStore.list_objects(s) == Enum.sort([h1, h2, h3])
  end