  test "success response echoes the resolved vendor content-type" do
    conn = call("/api/users/1", [{"accept", "application/vnd.acme.v1+json"}])
    assert content_type(conn) =~ "application/vnd.acme.v1+json"

    conn2 = call("/api/users/1", [{"accept", "application/vnd.acme.v2+json"}])
    assert content_type(conn2) =~ "application/vnd.acme.v2+json"
  end