  test "default response is identical to explicit v2 request" do
    conn_default = call(:get, "/api/users/2")
    conn_v2 = call(:get, "/api/users/2", [{"accept-version", "v2"}])

    assert json_body(conn_default) == json_body(conn_v2)
  end