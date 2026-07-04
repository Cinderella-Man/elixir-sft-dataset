  test "unsupported vendor version is skipped in favor of a supported one" do
    conn =
      call("/api/users/1", [
        {"accept", "application/vnd.acme.v9+json;q=1.0, application/vnd.acme.v1+json;q=0.3"}
      ])

    assert conn.status == 200
    assert content_type(conn) =~ "v1"
  end