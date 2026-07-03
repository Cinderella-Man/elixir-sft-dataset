  test "v2 flattens name and drops country" do
    conn = call("/api/v2/users/1")

    assert conn.status == 200
    body = json_body(conn)

    assert body["id"] == "1"
    assert body["first_name"] == "Alice"
    assert body["last_name"] == "Smith"
    assert body["created_at"] == "2024-01-15T10:30:00Z"
    refute Map.has_key?(body, "country")
    refute Map.has_key?(body, "name")
  end