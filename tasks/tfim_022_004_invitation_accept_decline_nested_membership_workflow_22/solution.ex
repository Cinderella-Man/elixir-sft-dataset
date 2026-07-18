  test "POST decline removes the invitation without making a member", %{store: store} do
    post_invite(store, "team-1", "dave", "token-alice")

    conn = post_decline(store, "team-1", "dave", "token-dave")
    assert conn.status == 200
    assert json_body(conn)["declined"] == "dave"

    refute TeamStore.is_member?(store, "team-1", "dave")

    listing = get_invitations(store, "team-1", "token-alice")
    refute "dave" in json_body(listing)["invitations"]
  end