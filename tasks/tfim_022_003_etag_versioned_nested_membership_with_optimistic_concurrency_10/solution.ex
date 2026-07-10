  test "POST without If-Match header returns 428", %{store: store} do
    conn = post_member_no_match(store, "team-1", "carol", "token-alice")
    assert conn.status == 428
    assert json_body(conn)["error"] == "precondition_required"
  end