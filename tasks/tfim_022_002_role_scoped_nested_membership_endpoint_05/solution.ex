  test "GET returns 401 without auth", %{store: store} do
    conn = get_members(store, "team-1", nil)
    assert conn.status == 401
    assert json_body(conn)["error"] == "unauthorized"
  end