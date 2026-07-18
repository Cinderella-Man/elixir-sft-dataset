  test "update_branch on unknown branch returns no_branch", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c} = ObjectStore.commit(s, t, nil, "one", "alice")
    assert {:error, :no_branch} = ObjectStore.update_branch(s, "missing", c, c)
  end