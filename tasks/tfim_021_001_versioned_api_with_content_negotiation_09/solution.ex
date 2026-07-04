  test "406 response includes list of supported versions" do
    conn = call(:get, "/api/users/1", [{"accept-version", "v99"}])

    assert conn.status == 406
    body = json_body(conn)

    assert is_list(body["supported"])
    assert "v1" in body["supported"]
    assert "v2" in body["supported"]
  end