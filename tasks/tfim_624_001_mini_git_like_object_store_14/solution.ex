  test "log of a single root commit returns one entry", %{store: s} do
    {:ok, bh} = ObjectStore.store(s, "data")
    {:ok, th} = ObjectStore.tree(s, [%{name: "f", hash: bh, type: :blob}])
    {:ok, ch} = ObjectStore.commit(s, th, nil, "root commit", "alice")

    {:ok, entries} = ObjectStore.log(s, ch)

    assert length(entries) == 1
    [entry] = entries
    assert entry.hash == ch
    assert entry.message == "root commit"
    assert entry.author == "alice"
    assert entry.tree == th
    assert entry.parent == nil
  end