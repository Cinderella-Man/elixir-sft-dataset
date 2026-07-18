  test "returns 404 for a non-existent user with v2" do
    conn = call(:get, "/api/users/999", [{"accept-version", "v2"}])

    assert conn.status == 404
  end