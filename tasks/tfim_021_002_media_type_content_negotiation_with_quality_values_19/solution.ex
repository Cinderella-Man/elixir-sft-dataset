  test "missing user returns 404 with json content type" do
    conn = call("/api/users/999", [{"accept", "application/vnd.acme.v2+json"}])
    assert conn.status == 404
    assert json_body(conn)["error"] =~ "not found"
    assert content_type(conn) =~ "application/json"
  end