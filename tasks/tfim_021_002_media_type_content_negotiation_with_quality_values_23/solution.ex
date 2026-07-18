  test "unrelated media type is ignored while a supported vendor range still wins" do
    conn =
      call("/api/users/1", [
        {"accept", "text/html;q=1.0, application/vnd.acme.v1+json;q=0.2"}
      ])

    assert conn.status == 200
    assert content_type(conn) =~ "application/vnd.acme.v1+json"
    assert json_body(conn)["name"] == "Alice Smith"
  end