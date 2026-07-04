  test "second user is correct in deprecated v1" do
    conn = call("/api/users/2", [{"accept-version", "v1"}])
    assert json_body(conn)["name"] == "Bob Jones"
  end