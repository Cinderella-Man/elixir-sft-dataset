  test "tree stores a tree object and returns its hash", %{store: s} do
    {:ok, blob_hash} = ObjectStore.store(s, "file content")

    entries = [%{name: "README.md", hash: blob_hash, type: :blob}]
    {:ok, tree_hash} = ObjectStore.tree(s, entries)

    assert tree_hash =~ ~r/^[0-9a-f]{40}$/
    # The tree object itself should be retrievable as raw content
    assert {:ok, _raw} = ObjectStore.retrieve(s, tree_hash)
  end