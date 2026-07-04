  test "application/json resolves to the default version" do
    conn = call("/api/users/1", [{"accept", "application/json"}])
    assert content_type(conn) =~ "v2"
  end