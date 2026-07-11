  test "commit is deterministic", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c1} = ObjectStore.commit(s, t, nil, "msg", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, nil, "msg", "alice")
    assert c1 == c2
  end