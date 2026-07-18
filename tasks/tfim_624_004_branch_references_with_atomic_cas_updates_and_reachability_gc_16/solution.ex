  test "update_branch with unknown new hash returns not_found", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c1} = ObjectStore.commit(s, t, nil, "one", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c1)
    assert {:error, :not_found} = ObjectStore.update_branch(s, "main", c1, sha1("ghost"))
  end