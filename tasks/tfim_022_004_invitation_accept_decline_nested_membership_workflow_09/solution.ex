  test "GET invitations returns 404 for a non-existent team", %{store: store} do
    conn = get_invitations(store, "ghost-team", "token-alice")
    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end