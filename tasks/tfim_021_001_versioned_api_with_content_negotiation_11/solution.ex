  test "returns 404 for a non-existent user with v1" do
    conn = call(:get, "/api/users/999", [{"accept-version", "v1"}])

    assert conn.status == 404
    body = json_body(conn)
    assert body["error"] =~ "not found"
  end