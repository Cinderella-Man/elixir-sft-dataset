  test "v1 vendor media type returns v1 shape" do
    conn = call("/api/users/1", [{"accept", "application/vnd.acme.v1+json"}])

    assert conn.status == 200
    body = json_body(conn)

    assert body["name"] == "Alice Smith"
    assert body["email"] == "alice@example.com"
    refute Map.has_key?(body, "first_name")
    refute Map.has_key?(body, "created_at")
  end