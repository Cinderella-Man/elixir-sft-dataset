  test "supported list excludes the retired version in 410 responses too" do
    conn = call("/api/users/1", [{"accept-version", "v0"}])
    assert json_body(conn)["supported"] == ["v1", "v2"]
  end