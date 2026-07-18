  test "list_branches returns all branches", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c1} = ObjectStore.commit(s, t, nil, "a", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, nil, "b", "bob")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)
    {:ok, _} = ObjectStore.create_branch(s, "dev", c2)

    assert ObjectStore.list_branches(s) == %{"main" => c1, "dev" => c2}
  end