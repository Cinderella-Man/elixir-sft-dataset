  test "POST accept removes the invitation from the pending list", %{store: store} do
    post_invite(store, "team-1", "dave", "token-alice")
    post_accept(store, "team-1", "dave", "token-dave")

    listing = get_invitations(store, "team-1", "token-alice")
    refute "dave" in json_body(listing)["invitations"]
  end