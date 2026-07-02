  test "v2 returns {first_name, last_name, email, created_at} shape" do
    conn = call(:get, "/api/users/1", [{"accept-version", "v2"}])

    assert conn.status == 200
    body = json_body(conn)

    assert Map.has_key?(body, "first_name")
    assert Map.has_key?(body, "last_name")
    assert Map.has_key?(body, "email")
    assert Map.has_key?(body, "created_at")

    # v2 must NOT contain the v1 combined name field
    refute Map.has_key?(body, "name")
  end