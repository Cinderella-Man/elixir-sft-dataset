  test "ApiVersion initialised with no options falls back to the v2 default" do
    opts = LifecycleApi.Plugs.ApiVersion.init([])
    conn = LifecycleApi.Plugs.ApiVersion.call(conn(:get, "/api/users/1"), opts)

    assert conn.assigns[:api_version] == "v2"
    refute conn.halted
    assert Plug.Conn.get_resp_header(conn, "deprecation") == []
    assert Plug.Conn.get_resp_header(conn, "warning") == []
  end