  test "GET returns 200 for any member of the team", %{store: store} do
    conn = get_members(store, "team-1", "token-bob")
    assert conn.status == 200
    assert "alice" in json_body(conn)["members"]
  end