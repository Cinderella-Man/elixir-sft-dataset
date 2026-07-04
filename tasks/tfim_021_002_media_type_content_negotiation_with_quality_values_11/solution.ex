  test "only-unsupported vendor version returns 406" do
    conn = call("/api/users/1", [{"accept", "application/vnd.acme.v9+json"}])

    assert conn.status == 406
    body = json_body(conn)
    assert body["error"] =~ "unsupported"
    assert "v1" in body["supported"]
    assert "v2" in body["supported"]
    assert content_type(conn) =~ "application/json"
  end