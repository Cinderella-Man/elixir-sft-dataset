  test "gc sweeps everything when there are no branches", %{store: s} do
    {:ok, tree} = ObjectStore.store(s, "tree-content")
    {:ok, _c1} = ObjectStore.commit(s, tree, nil, "root", "alice")

    assert {:ok, 2} = ObjectStore.gc(s)
    assert {:error, :not_found} = ObjectStore.retrieve(s, tree)
    assert ObjectStore.list_branches(s) == %{}
  end