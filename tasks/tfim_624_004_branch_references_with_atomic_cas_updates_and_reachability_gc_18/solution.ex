  test "delete_branch removes a branch", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c} = ObjectStore.commit(s, t, nil, "root", "alice")
    {:ok, _} = ObjectStore.create_branch(s, "main", c)

    assert :ok = ObjectStore.delete_branch(s, "main")
    assert {:error, :no_branch} = ObjectStore.branch_head(s, "main")
    assert {:error, :no_branch} = ObjectStore.delete_branch(s, "main")
  end