  test "v1 combines the name and drops created_at and country" do
    conn = call("/api/v1/users/1")

    assert conn.status == 200
    body = json_body(conn)

    assert body["id"] == "1"
    assert body["name"] == "Alice Smith"
    assert body["email"] == "alice@example.com"
    refute Map.has_key?(body, "first_name")
    refute Map.has_key?(body, "last_name")
    refute Map.has_key?(body, "created_at")
    refute Map.has_key?(body, "country")
  end