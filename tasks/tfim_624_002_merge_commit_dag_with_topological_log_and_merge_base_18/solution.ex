  test "log of a diamond lists each reachable commit exactly once", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, root} = ObjectStore.commit(s, t, [], "root", "alice")
    {:ok, a} = ObjectStore.commit(s, t, [root], "a", "alice")
    {:ok, b} = ObjectStore.commit(s, t, [root], "b", "bob")
    {:ok, m} = ObjectStore.commit(s, t, [a, b], "merge", "carol")

    {:ok, log} = ObjectStore.log(s, m)
    hashes = Enum.map(log, & &1.hash)

    assert length(hashes) == 4
    assert Enum.uniq(hashes) == hashes
    assert MapSet.new(hashes) == MapSet.new([m, a, b, root])
    assert hd(log).hash == m
    assert order_ok?(log)
  end