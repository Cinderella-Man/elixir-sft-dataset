  test "unsupported version returns 406 even for non-existent user" do
    conn = call(:get, "/api/users/999", [{"accept-version", "v3"}])

    # The version plug should halt before the router tries to look up the user
    assert conn.status == 406
  end