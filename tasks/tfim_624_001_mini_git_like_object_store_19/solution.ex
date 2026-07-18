  test "tree with empty entries list", %{store: s} do
    {:ok, tree_hash} = ObjectStore.tree(s, [])
    assert tree_hash =~ ~r/^[0-9a-f]{40}$/
    assert {:ok, _raw} = ObjectStore.retrieve(s, tree_hash)
  end