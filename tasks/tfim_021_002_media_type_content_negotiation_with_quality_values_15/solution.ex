  test "wildcard with q=0 does not resolve to the default version" do
    conn = call("/api/users/1", [{"accept", "*/*;q=0"}])

    assert conn.status == 406
  end