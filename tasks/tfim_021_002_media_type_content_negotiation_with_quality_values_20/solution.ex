  test "second user is correct in v1" do
    conn = call("/api/users/2", [{"accept", "application/vnd.acme.v1+json"}])
    body = json_body(conn)
    assert body["name"] == "Bob Jones"
    assert body["email"] == "bob@example.com"
  end