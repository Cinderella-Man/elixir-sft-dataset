  test "commit with a parent references the parent hash", %{store: s} do
    {:ok, bh} = ObjectStore.store(s, "v1")
    {:ok, th} = ObjectStore.tree(s, [%{name: "f.txt", hash: bh, type: :blob}])
    {:ok, c1} = ObjectStore.commit(s, th, nil, "first", "alice")

    {:ok, bh2} = ObjectStore.store(s, "v2")
    {:ok, th2} = ObjectStore.tree(s, [%{name: "f.txt", hash: bh2, type: :blob}])
    {:ok, c2} = ObjectStore.commit(s, th2, c1, "second", "bob")

    assert c1 != c2
  end