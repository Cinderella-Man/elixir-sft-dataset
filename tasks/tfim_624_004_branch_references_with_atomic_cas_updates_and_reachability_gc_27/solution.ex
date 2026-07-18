  test "gc keeps a tree shared by multiple reachable commits", %{store: s} do
    {:ok, tree} = ObjectStore.store(s, "shared-tree")
    {:ok, c1} = ObjectStore.commit(s, tree, nil, "one", "alice")
    {:ok, c2} = ObjectStore.commit(s, tree, c1, "two", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c2)

    assert {:ok, 0} = ObjectStore.gc(s)
    assert {:ok, "shared-tree"} = ObjectStore.retrieve(s, tree)
    assert {:ok, _} = ObjectStore.retrieve(s, c1)
    assert {:ok, _} = ObjectStore.retrieve(s, c2)
  end