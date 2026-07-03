  test "no header defaults to active v2" do
    conn = call("/api/users/1")
    assert conn.status == 200
    assert Map.has_key?(json_body(conn), "first_name")
    assert Plug.Conn.get_resp_header(conn, "deprecation") == []
  end