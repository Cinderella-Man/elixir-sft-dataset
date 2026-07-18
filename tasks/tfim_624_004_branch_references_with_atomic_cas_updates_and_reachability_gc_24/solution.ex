  test "gc is idempotent once nothing is unreachable", %{store: s} do
    {:ok, tree} = ObjectStore.store(s, "tree-content")
    {:ok, c1} = ObjectStore.commit(s, tree, nil, "root", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)

    assert {:ok, 0} = ObjectStore.gc(s)
    assert {:ok, 0} = ObjectStore.gc(s)
    assert {:ok, _} = ObjectStore.retrieve(s, c1)
    assert {:ok, _} = ObjectStore.retrieve(s, tree)
  end