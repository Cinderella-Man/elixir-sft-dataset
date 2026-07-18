  test "merge_base returns the nearest shared ancestor, not an older common one", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, root} = ObjectStore.commit(s, t, [], "root", "alice")
    {:ok, mid} = ObjectStore.commit(s, t, [root], "mid", "alice")
    {:ok, a} = ObjectStore.commit(s, t, [mid], "a", "alice")
    {:ok, b} = ObjectStore.commit(s, t, [mid], "b", "bob")

    # root is also a common ancestor, but it is a proper ancestor of mid.
    assert {:ok, ^mid} = ObjectStore.merge_base(s, a, b)
  end