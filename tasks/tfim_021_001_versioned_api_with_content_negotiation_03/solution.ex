  test "v1 name is first_name + last_name combined" do
    conn = call(:get, "/api/users/1", [{"accept-version", "v1"}])
    body = json_body(conn)

    assert body["name"] == "Alice Smith"
    assert body["email"] == "alice@example.com"
  end