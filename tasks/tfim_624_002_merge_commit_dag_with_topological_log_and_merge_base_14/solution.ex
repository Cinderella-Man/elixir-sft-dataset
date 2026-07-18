  test "merge_base returns not_found when a hash is missing", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "first", "alice")

    assert {:error, :not_found} =
             ObjectStore.merge_base(s, c1, "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
  end