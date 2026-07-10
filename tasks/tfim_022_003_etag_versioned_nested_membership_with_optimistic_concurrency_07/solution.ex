  test "GET returns 404 for non-existent team", %{store: store} do
    conn = get_members(store, "no-such-team", "token-alice")
    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end