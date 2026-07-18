  test "optimistic concurrency: two writers with the same base version, second is stale", %{
    store: store
  } do
    v = version(store, "team-1")
    c1 = post_member(store, "team-1", "carol", "token-alice", to_string(v))
    c2 = post_member(store, "team-1", "dave", "token-alice", to_string(v))
    assert c1.status == 201
    assert c2.status == 412
  end