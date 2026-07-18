  test "POST with a trailing-garbage If-Match returns 412 even at the live version", %{
    store: store
  } do
    v = version(store, "team-1")
    conn = post_member(store, "team-1", "carol", "token-alice", "#{v}x")

    assert conn.status == 412
    assert json_body(conn)["error"] == "precondition_failed"
    refute TeamStore.is_member?(store, "team-1", "carol")
    assert version(store, "team-1") == v
  end