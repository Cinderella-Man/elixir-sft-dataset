  test "returns 404 for a non-existent user with default version" do
    conn = call(:get, "/api/users/999")

    assert conn.status == 404
  end