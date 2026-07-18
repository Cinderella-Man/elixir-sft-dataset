  test "create_branch can point a blob-backed branch at any stored object", %{store: s} do
    {:ok, blob} = ObjectStore.store(s, "loose")
    assert {:ok, "b"} = ObjectStore.create_branch(s, "b", blob)
    assert {:ok, ^blob} = ObjectStore.branch_head(s, "b")
  end