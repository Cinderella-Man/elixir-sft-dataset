  test "unrelated media type only returns 406" do
    conn = call("/api/users/1", [{"accept", "text/html"}])
    assert conn.status == 406
  end