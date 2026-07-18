  test "merge_base of two independent roots has no common ancestor", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, r1} = ObjectStore.commit(s, t, [], "root one", "alice")
    {:ok, r2} = ObjectStore.commit(s, t, [], "root two", "bob")

    assert {:error, :no_merge_base} = ObjectStore.merge_base(s, r1, r2)
  end