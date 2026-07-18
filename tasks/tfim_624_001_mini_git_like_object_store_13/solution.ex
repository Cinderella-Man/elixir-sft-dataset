  test "same commit metadata produces the same hash (deterministic)", %{store: s} do
    {:ok, bh} = ObjectStore.store(s, "data")
    {:ok, th} = ObjectStore.tree(s, [%{name: "f", hash: bh, type: :blob}])

    {:ok, c1} = ObjectStore.commit(s, th, nil, "msg", "author")
    {:ok, c2} = ObjectStore.commit(s, th, nil, "msg", "author")

    assert c1 == c2
  end