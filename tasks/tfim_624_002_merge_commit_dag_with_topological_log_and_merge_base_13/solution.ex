  test "merge_base where one commit is an ancestor of the other", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "first", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, [c1], "second", "bob")

    assert {:ok, ^c1} = ObjectStore.merge_base(s, c2, c1)
  end