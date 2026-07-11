  test "tree can contain nested tree references", %{store: s} do
    {:ok, blob_hash} = ObjectStore.store(s, "nested content")

    {:ok, subtree_hash} =
      ObjectStore.tree(s, [%{name: "inner.txt", hash: blob_hash, type: :blob}])

    entries = [
      %{name: "subdir", hash: subtree_hash, type: :tree},
      %{name: "root.txt", hash: blob_hash, type: :blob}
    ]

    {:ok, root_tree_hash} = ObjectStore.tree(s, entries)
    assert root_tree_hash =~ ~r/^[0-9a-f]{40}$/
    assert {:ok, _raw} = ObjectStore.retrieve(s, root_tree_hash)
  end