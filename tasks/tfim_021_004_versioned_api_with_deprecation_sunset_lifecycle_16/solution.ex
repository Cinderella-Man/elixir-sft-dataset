  test "unknown version 406 response is served as application/json" do
    conn = call("/api/users/1", [{"accept-version", "v9"}])

    assert conn.status == 406
    assert content_type(conn) =~ "application/json"
    assert conn.halted
  end