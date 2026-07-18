  test "second user is also accessible and correct in v2" do
    conn = call(:get, "/api/users/2", [{"accept-version", "v2"}])

    assert conn.status == 200
    body = json_body(conn)

    assert body["first_name"] == "Bob"
    assert body["last_name"] == "Jones"
    assert body["email"] == "bob@example.com"
    assert body["created_at"] == "2024-06-20T14:00:00Z"
  end