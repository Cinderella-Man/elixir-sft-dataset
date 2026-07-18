  test "missing q defaults to 1.0 and outranks an explicit lower q" do
    conn =
      call("/api/users/1", [
        {"accept", "application/vnd.acme.v1+json, application/vnd.acme.v2+json;q=0.9"}
      ])

    assert conn.status == 200
    assert content_type(conn) =~ "v1"
    assert json_body(conn)["name"] == "Alice Smith"

    later =
      call("/api/users/1", [
        {"accept", "application/vnd.acme.v2+json;q=0.9, application/vnd.acme.v1+json"}
      ])

    assert later.status == 200
    assert content_type(later) =~ "v1"
  end