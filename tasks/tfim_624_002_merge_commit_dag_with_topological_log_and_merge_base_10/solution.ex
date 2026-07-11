  test "log of a merge commit includes both branches and orders ancestors after", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "branch a root", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, [], "branch b root", "bob")
    {:ok, m} = ObjectStore.commit(s, t, [c1, c2], "merge", "carol")

    {:ok, log} = ObjectStore.log(s, m)
    assert length(log) == 3
    assert hd(log).hash == m
    assert hd(log).parents == [c1, c2]
    assert order_ok?(log)
    assert MapSet.new(Enum.map(log, & &1.hash)) == MapSet.new([m, c1, c2])
  end