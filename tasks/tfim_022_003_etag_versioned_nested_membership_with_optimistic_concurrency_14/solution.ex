  test "POST with a non-numeric If-Match returns 412 and writes nothing", %{store: store} do
    v = version(store, "team-1")
    conn = post_member(store, "team-1", "carol", "token-alice", "abc")

    assert conn.status == 412
    assert json_body(conn)["error"] == "precondition_failed"
    refute TeamStore.is_member?(store, "team-1", "carol")
    assert version(store, "team-1") == v
  end