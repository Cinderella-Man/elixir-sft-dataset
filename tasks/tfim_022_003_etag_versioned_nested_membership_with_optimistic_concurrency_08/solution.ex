  test "POST with matching If-Match returns 201 and increments version", %{store: store} do
    v = version(store, "team-1")
    conn = post_member(store, "team-1", "carol", "token-alice", to_string(v))

    assert conn.status == 201
    body = json_body(conn)
    assert body["added"] == "carol"
    assert body["version"] == v + 1
    assert etag(conn) == to_string(v + 1)
    assert TeamStore.is_member?(store, "team-1", "carol")
  end