  test "success response is application/json" do
    conn = call("/api/users/1", [{"accept-version", "v2"}])
    assert content_type(conn) =~ "application/json"
  end