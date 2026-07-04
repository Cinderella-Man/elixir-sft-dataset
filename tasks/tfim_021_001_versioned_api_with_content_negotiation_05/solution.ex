  test "v2 returns correct field values" do
    conn = call(:get, "/api/users/1", [{"accept-version", "v2"}])
    body = json_body(conn)

    assert body["first_name"] == "Alice"
    assert body["last_name"] == "Smith"
    assert body["email"] == "alice@example.com"
    assert body["created_at"] == "2024-01-15T10:30:00Z"
  end