  test "update_branch to the same hash is a no-op success", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c1} = ObjectStore.commit(s, t, nil, "one", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)
    assert {:ok, ^c1} = ObjectStore.update_branch(s, "main", c1, c1)
    assert {:ok, ^c1} = ObjectStore.branch_head(s, "main")
  end