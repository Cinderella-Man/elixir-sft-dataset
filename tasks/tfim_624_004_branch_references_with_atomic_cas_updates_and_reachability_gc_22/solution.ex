  test "gc removes an unreferenced loose blob but keeps commit and tree", %{store: s} do
    {:ok, tree} = ObjectStore.store(s, "tree-content")
    {:ok, dangling} = ObjectStore.store(s, "dangling blob")
    {:ok, c1} = ObjectStore.commit(s, tree, nil, "root", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)

    assert {:ok, 1} = ObjectStore.gc(s)
    assert {:error, :not_found} = ObjectStore.retrieve(s, dangling)
    assert {:ok, _} = ObjectStore.retrieve(s, c1)
    assert {:ok, "tree-content"} = ObjectStore.retrieve(s, tree)
  end