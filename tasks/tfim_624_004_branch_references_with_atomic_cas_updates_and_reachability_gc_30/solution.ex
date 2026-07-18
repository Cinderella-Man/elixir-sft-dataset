  test "gc keeps a grandparent commit reachable only through a multi-hop parent chain", %{
    store: s
  } do
    {:ok, tree} = ObjectStore.store(s, "tree-content")
    {:ok, c1} = ObjectStore.commit(s, tree, nil, "one", "alice")
    {:ok, c2} = ObjectStore.commit(s, tree, c1, "two", "alice")
    {:ok, c3} = ObjectStore.commit(s, tree, c2, "three", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c3)

    assert {:ok, 0} = ObjectStore.gc(s)
    assert {:ok, _} = ObjectStore.retrieve(s, c1)
    assert {:ok, _} = ObjectStore.retrieve(s, c2)
    assert {:ok, _} = ObjectStore.retrieve(s, c3)
  end