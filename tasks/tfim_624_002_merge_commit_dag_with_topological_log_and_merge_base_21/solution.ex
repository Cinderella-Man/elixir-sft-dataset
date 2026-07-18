  test "merge_base of a commit with itself returns that commit", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "first", "alice")
    {:ok, c2} = ObjectStore.commit(s, t, [c1], "second", "bob")

    assert {:ok, ^c2} = ObjectStore.merge_base(s, c2, c2)
  end