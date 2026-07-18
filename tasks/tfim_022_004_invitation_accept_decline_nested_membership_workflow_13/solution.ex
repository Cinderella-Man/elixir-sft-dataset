  test "POST invitations returns 403 when inviter is not a member", %{store: store} do
    conn = post_invite(store, "team-1", "dave", "token-carol")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end