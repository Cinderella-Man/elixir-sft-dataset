  test "POST invitations returns 409 already_invited on a duplicate invite", %{store: store} do
    assert post_invite(store, "team-1", "dave", "token-alice").status == 201

    conn = post_invite(store, "team-1", "dave", "token-bob")
    assert conn.status == 409
    assert json_body(conn)["error"] == "already_invited"
  end