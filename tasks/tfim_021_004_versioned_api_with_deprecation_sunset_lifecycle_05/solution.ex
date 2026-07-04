  test "retired v0 returns 410 Gone" do
    conn = call("/api/users/1", [{"accept-version", "v0"}])

    assert conn.status == 410
    body = json_body(conn)
    assert body["error"] =~ "retired"
    assert body["version"] == "v0"
    assert content_type(conn) =~ "application/json"
  end