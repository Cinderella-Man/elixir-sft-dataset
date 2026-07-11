  test "commit creates a commit object and returns its hash", %{store: s} do
    {:ok, blob_hash} = ObjectStore.store(s, "v1")
    {:ok, tree_hash} = ObjectStore.tree(s, [%{name: "file.txt", hash: blob_hash, type: :blob}])

    {:ok, commit_hash} = ObjectStore.commit(s, tree_hash, nil, "initial commit", "alice")

    assert commit_hash =~ ~r/^[0-9a-f]{40}$/
    assert {:ok, _raw} = ObjectStore.retrieve(s, commit_hash)
  end