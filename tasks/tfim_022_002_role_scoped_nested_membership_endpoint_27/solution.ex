  test "operations on team-1 do not affect team-2", %{store: store} do
    _ = post_member(store, "team-1", "carol", "token-alice")
    _ = delete_member(store, "team-1", "bob", "token-alice")

    conn = get_members(store, "team-2", "token-carol")
    assert conn.status == 200
    assert member(conn, "carol")["role"] == "owner"
  end