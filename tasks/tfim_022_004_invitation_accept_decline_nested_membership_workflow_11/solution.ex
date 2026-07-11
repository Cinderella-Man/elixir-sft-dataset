  test "POST invitations does not make the invited user a member yet", %{store: store} do
    post_invite(store, "team-1", "dave", "token-alice")

    refute TeamStore.is_member?(store, "team-1", "dave")

    conn = get_members(store, "team-1", "token-alice")
    refute "dave" in json_body(conn)["members"]
  end