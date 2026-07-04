  test "GET returns 200 with roles for a member", %{store: store} do
    conn = get_members(store, "team-1", "token-alice")
    assert conn.status == 200
    assert member(conn, "alice")["role"] == "owner"
    assert member(conn, "bob")["role"] == "member"
    assert member(conn, "dave")["role"] == "admin"
  end