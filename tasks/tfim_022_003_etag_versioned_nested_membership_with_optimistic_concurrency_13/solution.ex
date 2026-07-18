  test "POST with matching If-Match but duplicate member returns 409", %{store: store} do
    v = version(store, "team-1")
    conn = post_member(store, "team-1", "bob", "token-alice", to_string(v))
    assert conn.status == 409
    assert json_body(conn)["error"] == "conflict"
  end