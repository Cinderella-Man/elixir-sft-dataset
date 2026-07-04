  test "missing user with active version returns 404" do
    conn = call("/api/users/999", [{"accept-version", "v2"}])
    assert conn.status == 404
    assert json_body(conn)["error"] =~ "not found"
    assert content_type(conn) =~ "application/json"
  end