  test "invitations on team-1 do not affect team-2", %{store: store} do
    post_invite(store, "team-1", "dave", "token-alice")

    conn = get_members(store, "team-2", "token-carol")
    assert conn.status == 200
    assert json_body(conn)["members"] == ["carol"]

    listing = get_invitations(store, "team-2", "token-carol")
    assert json_body(listing)["invitations"] == []
  end