  test "POST returns 404 for non-existent team", %{store: store} do
    conn = post_member(store, "no-such-team", "alice", "token-alice")

    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end