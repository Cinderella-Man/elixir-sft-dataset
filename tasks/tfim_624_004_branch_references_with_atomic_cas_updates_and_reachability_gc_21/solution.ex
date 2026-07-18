  test "list_branches reflects deletions", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c} = ObjectStore.commit(s, t, nil, "root", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c)
    {:ok, _} = ObjectStore.create_branch(s, "dev", c)
    :ok = ObjectStore.delete_branch(s, "dev")

    assert ObjectStore.list_branches(s) == %{"main" => c}
  end