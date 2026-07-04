  test "highest q value wins" do
    conn =
      call("/api/users/1", [
        {"accept", "application/vnd.acme.v2+json;q=0.5, application/vnd.acme.v1+json;q=0.9"}
      ])

    assert conn.status == 200
    assert json_body(conn)["name"] == "Alice Smith"
    assert content_type(conn) =~ "v1"
  end