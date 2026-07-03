  test "v3 returns the canonical nested representation" do
    conn = call("/api/v3/users/1")

    assert conn.status == 200
    body = json_body(conn)

    assert body["id"] == "1"
    assert body["name"] == %{"first" => "Alice", "last" => "Smith"}
    assert body["email"] == "alice@example.com"
    assert body["created_at"] == "2024-01-15T10:30:00Z"
    assert body["country"] == "US"
  end