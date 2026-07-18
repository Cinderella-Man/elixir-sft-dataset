  test "POST returns 404 for non-existent team", %{store: store} do
    conn = post_member(store, "no-such-team", "carol", "token-alice", "0")
    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end