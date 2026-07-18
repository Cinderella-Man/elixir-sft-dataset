  test "gc keeps ancestors reachable through any branch", %{store: s} do
    {:ok, tree} = ObjectStore.store(s, "tree-content")
    {:ok, c1} = ObjectStore.commit(s, tree, nil, "one", "alice")
    {:ok, c2} = ObjectStore.commit(s, tree, c1, "two", "alice")
    {:ok, dangling} = ObjectStore.store(s, "junk")
    {:ok, _} = ObjectStore.create_branch(s, "main", c2)
    {:ok, _} = ObjectStore.create_branch(s, "old", c1)

    assert {:ok, 1} = ObjectStore.gc(s)
    assert {:error, :not_found} = ObjectStore.retrieve(s, dangling)
    assert {:ok, _} = ObjectStore.retrieve(s, c1)
    assert {:ok, _} = ObjectStore.retrieve(s, c2)
  end