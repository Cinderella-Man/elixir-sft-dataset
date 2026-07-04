  test "GET returns 404 for missing team", %{store: store} do
    conn = get_members(store, "ghost", "token-alice")
    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end