  test "trees with different entries produce different hashes", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "x")
    {:ok, h2} = ObjectStore.store(s, "y")

    {:ok, t1} = ObjectStore.tree(s, [%{name: "file", hash: h1, type: :blob}])
    {:ok, t2} = ObjectStore.tree(s, [%{name: "file", hash: h2, type: :blob}])

    assert t1 != t2
  end