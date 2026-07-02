  test "v1 returns {name, email} shape" do
    conn = call(:get, "/api/users/1", [{"accept-version", "v1"}])

    assert conn.status == 200
    body = json_body(conn)

    assert Map.has_key?(body, "name")
    assert Map.has_key?(body, "email")

    # v1 must NOT contain v2-only fields
    refute Map.has_key?(body, "first_name")
    refute Map.has_key?(body, "last_name")
    refute Map.has_key?(body, "created_at")
  end