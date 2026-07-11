  test "identical commit arguments produce the same hash", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tc")
    {:ok, c1} = ObjectStore.commit(s, t, [], "msg", "author")
    {:ok, c2} = ObjectStore.commit(s, t, [], "msg", "author")
    assert c1 == c2
  end