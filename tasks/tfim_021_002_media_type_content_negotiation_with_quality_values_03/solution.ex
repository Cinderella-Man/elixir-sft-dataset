  test "v2 vendor media type returns v2 shape" do
    conn = call("/api/users/1", [{"accept", "application/vnd.acme.v2+json"}])

    assert conn.status == 200
    body = json_body(conn)

    assert body["first_name"] == "Alice"
    assert body["last_name"] == "Smith"
    assert body["created_at"] == "2024-01-15T10:30:00Z"
    refute Map.has_key?(body, "name")
  end