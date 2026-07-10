  test "GET returns 200 with members, version and ETag header", %{store: store} do
    v = version(store, "team-1")
    conn = get_members(store, "team-1", "token-alice")

    assert conn.status == 200
    body = json_body(conn)
    assert "alice" in body["members"]
    assert "bob" in body["members"]
    refute "carol" in body["members"]
    assert body["version"] == v
    assert etag(conn) == to_string(v)
  end