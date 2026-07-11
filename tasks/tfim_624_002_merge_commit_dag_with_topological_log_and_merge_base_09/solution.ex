  test "log walks a linear chain newest-to-oldest", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "first", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, [c1], "second", "bob")
    {:ok, c3} = ObjectStore.commit(s, t, [c2], "third", "carol")

    {:ok, log} = ObjectStore.log(s, c3)
    assert length(log) == 3
    assert hd(log).hash == c3
    assert order_ok?(log)
    assert MapSet.new(Enum.map(log, & &1.hash)) == MapSet.new([c1, c2, c3])
  end