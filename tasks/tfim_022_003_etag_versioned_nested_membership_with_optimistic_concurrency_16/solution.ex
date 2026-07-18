  test "POST returns 403 when user is not a member", %{store: store} do
    v = version(store, "team-1")
    conn = post_member(store, "team-1", "carol", "token-carol", to_string(v))
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end