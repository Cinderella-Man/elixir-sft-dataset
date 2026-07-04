  test "unsupported version returns 400 even for a missing user" do
    conn = call("/api/v9/users/999")
    assert conn.status == 400
  end