  test "unsupported version returns 406 Not Acceptable" do
    conn = call(:get, "/api/users/1", [{"accept-version", "v3"}])

    assert conn.status == 406
    body = json_body(conn)

    assert body["error"] =~ "unsupported"
  end