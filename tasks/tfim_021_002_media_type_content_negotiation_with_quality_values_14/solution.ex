  test "range with negative q is discarded and yields 406" do
    conn = call("/api/users/1", [{"accept", "application/vnd.acme.v2+json;q=-0.5"}])

    assert conn.status == 406
  end