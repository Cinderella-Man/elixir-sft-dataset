  test "valid version + missing user returns 404" do
    conn = call("/api/v2/users/999")
    assert conn.status == 404
    assert json_body(conn)["error"] =~ "not found"
  end