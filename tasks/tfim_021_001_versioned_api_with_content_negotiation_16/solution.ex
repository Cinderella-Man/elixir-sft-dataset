  test "404 response has application/json content type" do
    conn = call(:get, "/api/users/999")

    assert {"content-type", content_type} =
             List.keyfind(conn.resp_headers, "content-type", 0)

    assert content_type =~ "application/json"
  end