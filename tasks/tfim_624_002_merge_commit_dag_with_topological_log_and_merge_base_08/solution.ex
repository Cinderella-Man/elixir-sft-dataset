  test "different parents produce different commit hashes", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, base} = ObjectStore.commit(s, t, [], "base", "alice")
    {:ok, extra} = ObjectStore.commit(s, t, [], "extra", "alice")

    {:ok, one_parent} = ObjectStore.commit(s, t, [base], "x", "alice")
    {:ok, two_parents} = ObjectStore.commit(s, t, [base, extra], "x", "alice")
    assert one_parent != two_parents
  end