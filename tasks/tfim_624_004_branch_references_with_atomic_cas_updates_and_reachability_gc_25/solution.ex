  test "gc collects commits that became unreachable after a branch delete", %{store: s} do
    {:ok, tree} = ObjectStore.store(s, "tree-content")
    {:ok, c1} = ObjectStore.commit(s, tree, nil, "one", "alice")
    {:ok, c2} = ObjectStore.commit(s, tree, c1, "two", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)
    {:ok, ^c2} = ObjectStore.update_branch(s, "main", c1, c2)

    {:ok, orphan} = ObjectStore.commit(s, tree, nil, "independent root", "bob")
    {:ok, _} = ObjectStore.create_branch(s, "tmp", orphan)
    :ok = ObjectStore.delete_branch(s, "tmp")

    assert {:ok, 1} = ObjectStore.gc(s)
    assert {:error, :not_found} = ObjectStore.retrieve(s, orphan)
    assert {:ok, _} = ObjectStore.retrieve(s, c1)
    assert {:ok, _} = ObjectStore.retrieve(s, c2)
    assert {:ok, _} = ObjectStore.retrieve(s, tree)
    assert {:ok, ^c2} = ObjectStore.branch_head(s, "main")
  end