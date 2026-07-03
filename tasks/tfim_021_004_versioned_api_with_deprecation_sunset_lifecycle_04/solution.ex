  test "deprecated v1 serves the v1 shape but adds lifecycle headers" do
    conn = call("/api/users/1", [{"accept-version", "v1"}])

    assert conn.status == 200
    body = json_body(conn)
    assert body["name"] == "Alice Smith"
    refute Map.has_key?(body, "created_at")

    assert Plug.Conn.get_resp_header(conn, "deprecation") == ["true"]
    assert Plug.Conn.get_resp_header(conn, "sunset") == ["Sat, 01 Nov 2025 00:00:00 GMT"]

    [warning] = Plug.Conn.get_resp_header(conn, "warning")
    assert warning =~ "299"
    assert warning =~ "v1"
  end