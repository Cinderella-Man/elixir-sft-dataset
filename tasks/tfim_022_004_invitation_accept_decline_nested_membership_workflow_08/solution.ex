  test "GET invitations returns 403 for a non-member", %{store: store} do
    conn = get_invitations(store, "team-1", "token-carol")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end