  test "second user is correct in v1" do
    conn = call(:get, "/api/users/2", [{"accept-version", "v1"}])

    assert conn.status == 200
    body = json_body(conn)

    assert body["name"] == "Bob Jones"
    assert body["email"] == "bob@example.com"
  end