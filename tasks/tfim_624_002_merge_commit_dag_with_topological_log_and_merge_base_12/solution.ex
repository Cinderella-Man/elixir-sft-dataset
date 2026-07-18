  test "merge_base of a diamond returns the shared root", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, root} = ObjectStore.commit(s, t, [], "root", "alice")
    {:ok, a} = ObjectStore.commit(s, t, [root], "a", "alice")
    {:ok, b} = ObjectStore.commit(s, t, [root], "b", "bob")

    assert {:ok, ^root} = ObjectStore.merge_base(s, a, b)
  end