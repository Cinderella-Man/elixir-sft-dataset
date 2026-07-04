  test "unsupported path version returns 400" do
    conn = call("/api/v9/users/1")

    assert conn.status == 400
    body = json_body(conn)
    assert body["error"] =~ "unsupported"
    assert body["supported"] == ["v1", "v2", "v3"]
  end