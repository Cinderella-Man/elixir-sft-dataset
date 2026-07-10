  test "POST with stale If-Match returns 412", %{store: store} do
    v = version(store, "team-1")
    # First write succeeds and moves the version forward.
    assert post_member(store, "team-1", "carol", "token-alice", to_string(v)).status == 201
    # Second write still presenting the old version is rejected.
    conn = post_member(store, "team-1", "dave", "token-alice", to_string(v))
    assert conn.status == 412
    assert json_body(conn)["error"] == "precondition_failed"
  end