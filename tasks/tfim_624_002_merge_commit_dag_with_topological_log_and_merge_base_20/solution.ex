  test "reordering the parent list changes the commit hash", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, p1} = ObjectStore.commit(s, t, [], "p one", "alice")
    {:ok, p2} = ObjectStore.commit(s, t, [], "p two", "bob")

    {:ok, ab} = ObjectStore.commit(s, t, [p1, p2], "merge", "carol")
    {:ok, ba} = ObjectStore.commit(s, t, [p2, p1], "merge", "carol")
    {:ok, again} = ObjectStore.commit(s, t, [p1, p2], "merge", "carol")

    assert ab != ba
    assert ab == again

    {:ok, [entry | _]} = ObjectStore.log(s, ba)
    assert entry.parents == [p2, p1]
  end