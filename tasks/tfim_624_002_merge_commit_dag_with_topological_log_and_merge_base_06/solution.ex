  test "root commit (empty parents) is retrievable and has empty parents in log", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree-content")
    {:ok, c} = ObjectStore.commit(s, t, [], "root commit", "alice")

    assert c =~ ~r/^[0-9a-f]{40}$/
    assert {:ok, _raw} = ObjectStore.retrieve(s, c)

    {:ok, [entry]} = ObjectStore.log(s, c)
    assert entry.hash == c
    assert entry.tree == t
    assert entry.parents == []
    assert entry.message == "root commit"
    assert entry.author == "alice"
  end