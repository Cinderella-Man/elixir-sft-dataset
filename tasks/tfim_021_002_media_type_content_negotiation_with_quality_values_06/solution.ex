  test "equal q values break ties by earliest appearance" do
    conn =
      call("/api/users/1", [
        {"accept", "application/vnd.acme.v1+json, application/vnd.acme.v2+json"}
      ])

    assert content_type(conn) =~ "v1"
  end