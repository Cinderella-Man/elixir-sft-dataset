  test "deprecated v1 warning header matches the documented format exactly" do
    conn = call("/api/users/1", [{"accept-version", "v1"}])

    assert Plug.Conn.get_resp_header(conn, "warning") ==
             [~s(299 - "Deprecated API version v1")]
  end