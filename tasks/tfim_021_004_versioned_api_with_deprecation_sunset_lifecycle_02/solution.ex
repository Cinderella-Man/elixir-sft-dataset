  test "active v2 serves normally without deprecation headers" do
    conn = call("/api/users/1", [{"accept-version", "v2"}])

    assert conn.status == 200
    body = json_body(conn)
    assert body["first_name"] == "Alice"
    assert body["created_at"] == "2024-01-15T10:30:00Z"

    assert Plug.Conn.get_resp_header(conn, "deprecation") == []
    assert Plug.Conn.get_resp_header(conn, "sunset") == []
    assert Plug.Conn.get_resp_header(conn, "warning") == []
  end