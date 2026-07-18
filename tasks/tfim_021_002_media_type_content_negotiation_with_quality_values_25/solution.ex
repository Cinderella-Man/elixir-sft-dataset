  test "second user renders the full v2 shape from the store" do
    conn = call("/api/users/2", [{"accept", "application/vnd.acme.v2+json"}])

    assert conn.status == 200
    body = json_body(conn)
    assert body["first_name"] == "Bob"
    assert body["last_name"] == "Jones"
    assert body["email"] == "bob@example.com"
    assert body["created_at"] == "2024-06-20T14:00:00Z"
  end