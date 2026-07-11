  test "tree hash is deterministic regardless of entry order", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "content a")
    {:ok, h2} = ObjectStore.store(s, "content b")

    entries_asc = [
      %{name: "a.txt", hash: h1, type: :blob},
      %{name: "b.txt", hash: h2, type: :blob}
    ]

    entries_desc = [
      %{name: "b.txt", hash: h2, type: :blob},
      %{name: "a.txt", hash: h1, type: :blob}
    ]

    {:ok, tree1} = ObjectStore.tree(s, entries_asc)
    {:ok, tree2} = ObjectStore.tree(s, entries_desc)

    assert tree1 == tree2
  end