  test "random gibberish version returns 406" do
    conn = call(:get, "/api/users/1", [{"accept-version", "banana"}])

    assert conn.status == 406
  end