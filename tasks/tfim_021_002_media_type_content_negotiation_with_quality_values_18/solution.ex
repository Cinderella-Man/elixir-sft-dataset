  test "406 halts before user lookup even for a missing user" do
    conn = call("/api/users/999", [{"accept", "application/vnd.acme.v9+json"}])
    assert conn.status == 406
  end