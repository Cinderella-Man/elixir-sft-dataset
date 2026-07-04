  test "no Accept-Version header defaults to latest (v2)" do
    conn = call(:get, "/api/users/1")

    assert conn.status == 200
    body = json_body(conn)

    # Should match v2 shape
    assert Map.has_key?(body, "first_name")
    assert Map.has_key?(body, "last_name")
    assert Map.has_key?(body, "email")
    assert Map.has_key?(body, "created_at")
    refute Map.has_key?(body, "name")
  end