  test "ApiVersion honours a configured :default when the header is absent" do
    opts = LifecycleApi.Plugs.ApiVersion.init(default: "v1")
    conn = LifecycleApi.Plugs.ApiVersion.call(conn(:get, "/api/users/1"), opts)

    assert conn.assigns[:api_version] == "v1"
    refute conn.halted
    assert Plug.Conn.get_resp_header(conn, "deprecation") == ["true"]
    assert Plug.Conn.get_resp_header(conn, "sunset") == ["Sat, 01 Nov 2025 00:00:00 GMT"]
  end