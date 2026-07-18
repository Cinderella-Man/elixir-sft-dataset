  test "gc keeps the distinct tree of an ancestor commit", %{store: s} do
    {:ok, tree1} = ObjectStore.store(s, "old-tree")
    {:ok, tree2} = ObjectStore.store(s, "new-tree")
    {:ok, c1} = ObjectStore.commit(s, tree1, nil, "one", "alice")
    {:ok, c2} = ObjectStore.commit(s, tree2, c1, "two", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c2)

    assert {:ok, 0} = ObjectStore.gc(s)
    assert {:ok, "old-tree"} = ObjectStore.retrieve(s, tree1)
    assert {:ok, "new-tree"} = ObjectStore.retrieve(s, tree2)
  end