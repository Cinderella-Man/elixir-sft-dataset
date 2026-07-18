  test "all success responses have application/json content type" do
    conn = call(:get, "/api/users/1", [{"accept-version", "v1"}])

    assert {"content-type", content_type} =
             List.keyfind(conn.resp_headers, "content-type", 0)

    assert content_type =~ "application/json"
  end