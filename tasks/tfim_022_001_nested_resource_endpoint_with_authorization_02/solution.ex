  test "GET returns 200 with members for authorized user", %{store: store} do
    conn = get_members(store, "team-1", "token-alice")

    assert conn.status == 200
    body = json_body(conn)
    assert is_list(body["members"])
    assert "alice" in body["members"]
    assert "bob" in body["members"]
    refute "carol" in body["members"]
  end