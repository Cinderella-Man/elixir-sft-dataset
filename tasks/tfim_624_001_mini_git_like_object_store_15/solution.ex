  test "log walks a chain of three commits newest-to-oldest", %{store: s} do
    {:ok, bh} = ObjectStore.store(s, "v1")
    {:ok, th} = ObjectStore.tree(s, [%{name: "f", hash: bh, type: :blob}])

    {:ok, c1} = ObjectStore.commit(s, th, nil, "first", "alice")
    {:ok, c2} = ObjectStore.commit(s, th, c1, "second", "bob")
    {:ok, c3} = ObjectStore.commit(s, th, c2, "third", "carol")

    {:ok, log} = ObjectStore.log(s, c3)

    assert length(log) == 3
    assert Enum.map(log, & &1.message) == ["third", "second", "first"]
    assert Enum.map(log, & &1.author) == ["carol", "bob", "alice"]
    assert Enum.map(log, & &1.hash) == [c3, c2, c1]

    # Parent chain integrity
    assert Enum.at(log, 0).parent == c2
    assert Enum.at(log, 1).parent == c1
    assert Enum.at(log, 2).parent == nil
  end