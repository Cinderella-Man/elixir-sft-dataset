  test "update_branch moves the branch on a matching expected hash", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c1} = ObjectStore.commit(s, t, nil, "one", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, c1, "two", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)

    assert {:ok, ^c2} = ObjectStore.update_branch(s, "main", c1, c2)
    assert {:ok, ^c2} = ObjectStore.branch_head(s, "main")
  end