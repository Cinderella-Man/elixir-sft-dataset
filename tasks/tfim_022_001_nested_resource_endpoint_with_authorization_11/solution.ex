  test "POST returns 403 when user is not a team member", %{store: store} do
    conn = post_member(store, "team-1", "carol", "token-carol")

    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end