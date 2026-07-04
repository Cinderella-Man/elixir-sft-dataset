  test "missing user with deprecated version still returns 404 with lifecycle headers" do
    conn = call("/api/users/999", [{"accept-version", "v1"}])
    assert conn.status == 404
    assert Plug.Conn.get_resp_header(conn, "deprecation") == ["true"]
  end