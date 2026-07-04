  test "second user resolves through the chain in v1" do
    conn = call("/api/v1/users/2")
    body = json_body(conn)
    assert body["name"] == "Bob Jones"
    assert body["email"] == "bob@example.com"
  end