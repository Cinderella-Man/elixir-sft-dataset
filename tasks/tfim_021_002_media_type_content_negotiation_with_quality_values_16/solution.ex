  test "all ranges at q=0 leave nothing acceptable" do
    conn =
      call("/api/users/1", [
        {"accept", "application/vnd.acme.v1+json;q=0, application/vnd.acme.v2+json;q=0"}
      ])

    assert conn.status == 406
  end