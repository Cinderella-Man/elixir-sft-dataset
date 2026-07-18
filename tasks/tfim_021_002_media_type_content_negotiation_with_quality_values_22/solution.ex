  test "application/* resolves to the default version" do
    conn = call("/api/users/1", [{"accept", "application/*"}])

    assert conn.status == 200
    assert content_type(conn) =~ "v2"
    body = json_body(conn)
    assert body["first_name"] == "Alice"
    assert body["created_at"] == "2024-01-15T10:30:00Z"
    refute Map.has_key?(body, "name")
  end