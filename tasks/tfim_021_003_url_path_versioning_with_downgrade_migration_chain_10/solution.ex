  test "second user has its own country in v3" do
    conn = call("/api/v3/users/2")
    assert json_body(conn)["country"] == "GB"
  end