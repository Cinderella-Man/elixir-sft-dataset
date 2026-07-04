  test "GET is allowed for a plain member", %{store: store} do
    conn = get_members(store, "team-1", "token-bob")
    assert conn.status == 200
    assert member(conn, "alice")["role"] == "owner"
  end