  test "POST invitations returns 201 and lists the pending invitation", %{store: store} do
    conn = post_invite(store, "team-1", "dave", "token-alice")
    assert conn.status == 201
    assert json_body(conn)["invited"] == "dave"

    listing = get_invitations(store, "team-1", "token-alice")
    assert "dave" in json_body(listing)["invitations"]
  end