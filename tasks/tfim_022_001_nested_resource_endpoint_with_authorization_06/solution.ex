  test "GET returns 401 with invalid token", %{store: store} do
    conn = get_members(store, "team-1", "token-nobody")
    assert conn.status == 401
    assert json_body(conn)["error"] == "unauthorized"
  end