  test "POST invitations returns 404 for a non-existent team", %{store: store} do
    conn = post_invite(store, "ghost-team", "dave", "token-alice")
    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end