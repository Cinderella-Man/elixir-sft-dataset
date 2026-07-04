  test "retired version halts before user lookup" do
    conn = call("/api/users/999", [{"accept-version", "v0"}])
    assert conn.status == 410
  end