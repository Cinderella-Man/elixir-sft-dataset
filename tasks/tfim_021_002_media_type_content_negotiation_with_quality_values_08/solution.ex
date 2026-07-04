  test "*/* resolves to the default version" do
    conn = call("/api/users/1", [{"accept", "*/*"}])
    assert conn.status == 200
    assert content_type(conn) =~ "v2"
    assert Map.has_key?(json_body(conn), "created_at")
  end