  test "POST invalid role returns 400", %{store: store} do
    conn = post_member(store, "team-1", "erin", "token-alice", "superuser")
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_request"
  end