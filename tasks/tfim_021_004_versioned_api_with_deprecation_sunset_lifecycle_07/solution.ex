  test "unknown version returns 406 with requestable versions only" do
    conn = call("/api/users/1", [{"accept-version", "v9"}])

    assert conn.status == 406
    body = json_body(conn)
    assert body["error"] =~ "unsupported"
    assert body["supported"] == ["v1", "v2"]
    refute "v0" in body["supported"]
  end