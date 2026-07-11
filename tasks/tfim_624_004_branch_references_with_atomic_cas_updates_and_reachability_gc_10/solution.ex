  test "create_branch rejects a duplicate name", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c} = ObjectStore.commit(s, t, nil, "root", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c)
    assert {:error, :exists} = ObjectStore.create_branch(s, "main", c)
  end