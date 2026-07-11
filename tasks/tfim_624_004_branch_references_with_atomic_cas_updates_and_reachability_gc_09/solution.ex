  test "create_branch and branch_head", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c} = ObjectStore.commit(s, t, nil, "root", "alice")

    assert {:ok, "main"} = ObjectStore.create_branch(s, "main", c)
    assert {:ok, ^c} = ObjectStore.branch_head(s, "main")
  end