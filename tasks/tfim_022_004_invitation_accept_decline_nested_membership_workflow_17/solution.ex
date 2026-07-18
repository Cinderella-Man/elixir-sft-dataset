  test "POST accept turns the invitation into an active membership", %{store: store} do
    post_invite(store, "team-1", "dave", "token-alice")

    conn = post_accept(store, "team-1", "dave", "token-dave")
    assert conn.status == 200
    assert json_body(conn)["accepted"] == "dave"

    assert TeamStore.is_member?(store, "team-1", "dave")

    members = get_members(store, "team-1", "token-alice")
    assert "dave" in json_body(members)["members"]
  end